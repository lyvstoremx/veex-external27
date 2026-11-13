//
//  VXShim.swift
//  Resolución de contenedor y claves para el motor.
//  Los símbolos se buscan en la tabla del ejecutable, no con dlsym:
//  el binario nuevo no los exporta.
//

import Foundation
import CryptoKit
import Darwin
import MachO

func log(_ msg: String) {
    guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
    let url = dir.appendingPathComponent("veex.log")
    let line = Data(("[\(Date())] " + msg + "\n").utf8)
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile()
        h.write(line)
        try? h.close()
    } else {
        try? line.write(to: url)
    }
}

enum VXSym {
    static func find(_ name: String) -> UnsafeMutableRawPointer? {
        guard let hdr = _dyld_get_image_header(0) else { return nil }
        let slide = _dyld_get_image_vmaddr_slide(0)
        let base = UnsafeRawPointer(hdr)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)
        let want = "_" + name

        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SYMTAB) {
                let st = cursor.assumingMemoryBound(to: symtab_command.self)
                let count = Int(st.pointee.nsyms)
                guard count > 0 else { return nil }
                let syms = base.advanced(by: Int(st.pointee.symoff)).assumingMemoryBound(to: nlist_64.self)
                let strs = base.advanced(by: Int(st.pointee.stroff)).assumingMemoryBound(to: CChar.self)
                let size = Int(st.pointee.strsize)
                for i in 0..<count {
                    let s = syms[i]
                    let idx = Int(s.n_un.n_strx)
                    guard idx > 0, idx < size, s.n_value != 0 else { continue }
                    guard String(cString: strs.advanced(by: idx)) == want else { continue }
                    let addr = UInt64(bitPattern: slide) &+ s.n_value
                    return UnsafeMutableRawPointer(bitPattern: UInt(addr))
                }
                return nil
            }
            guard cmd.pointee.cmdsize > 0 else { return nil }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }
        return nil
    }

    static func count() -> Int {
        guard let hdr = _dyld_get_image_header(0) else { return 0 }
        let base = UnsafeRawPointer(hdr)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SYMTAB) {
                return Int(cursor.assumingMemoryBound(to: symtab_command.self).pointee.nsyms)
            }
            guard cmd.pointee.cmdsize > 0 else { return 0 }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }
        return 0
    }
}

enum VXContainers {
    private typealias PathFn = @convention(c) (
        UInt64, UnsafeMutableRawPointer, Bool, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> UnsafeMutableRawPointer?
    private typealias GrantFn = @convention(c) (UnsafeMutablePointer<CChar>, Bool, UnsafePointer<CChar>?, Bool) -> Int64

    private static var roots: [String: URL] = [:]
    private static var handles: [String: Int64] = [:]

    static func resolve(_ bundle: String) throws -> URL {
        if let cached = roots[bundle] { return cached }

        guard let sym = VXSym.find("MCMActivateContainerPath") else {
            log("vx: sin símbolo MCMActivateContainerPath")
            throw PatchPackageError.targetAppUnavailable(bundle)
        }
        let f = unsafeBitCast(sym, to: PathFn.self)
        let ns = bundle as NSString
        var err: UnsafeMutableRawPointer?
        guard let raw = f(2, Unmanaged.passUnretained(ns).toOpaque(), false, &err) else {
            log("vx: MCM no devolvió ruta para \(bundle)")
            throw PatchPackageError.targetAppUnavailable(bundle)
        }
        let path = Unmanaged<NSString>.fromOpaque(raw).takeUnretainedValue() as String

        if let gs = VXSym.find("bad_query") {
            let grant = unsafeBitCast(gs, to: GrantFn.self)
            let h = grant(strdup(path)!, true, nil, false)
            handles[bundle] = h
            log("vx: grant \(bundle) = \(h)")
        }

        let url = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        roots[bundle] = url
        log("vx: contenedor \(bundle) → \(path)")
        return url
    }
}

enum PatchKeyStore {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let d = base.appendingPathComponent("PatchKeys", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func account(for summary: PatchPackageSummary) -> String {
        let fingerprint = summary.keyFingerprint.map { String(format: "%02x", $0) }.joined()
        return "\(summary.packageID.uuidString).\(fingerprint)"
    }

    static func store(_ contentKey: Data, for summary: PatchPackageSummary) throws {
        guard contentKey.count == 32,
              Data(SHA256.hash(data: contentKey)) == summary.keyFingerprint else {
            throw PatchPackageError.keychainFailed
        }
        try contentKey.write(to: dir.appendingPathComponent(account(for: summary)))
    }

    static func load(for summary: PatchPackageSummary) throws -> Data? {
        let url = dir.appendingPathComponent(account(for: summary))
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard data.count == 32,
              Data(SHA256.hash(data: data)) == summary.keyFingerprint else {
            throw PatchPackageError.keychainFailed
        }
        return data
    }

    static func delete(for summary: PatchPackageSummary) throws {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(account(for: summary)))
    }
}

enum DevicePatchService {
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        try PatchTransaction.apply(
            project: project,
            backupRoot: try PatchProjectLibrary.backupRootURL(),
            containerResolver: VXContainers.resolve
        )
    }

    static func inspectRestore(receipt: PatchTransactionReceipt) throws -> PatchRestoreInspection {
        try PatchTransaction.inspectRestore(receipt: receipt, containerResolver: VXContainers.resolve)
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false
    ) throws {
        try PatchTransaction.restore(
            receipt: receipt,
            allowChangedTargets: allowChangedTargets,
            containerResolver: VXContainers.resolve
        )
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let root = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: root)
    }
}
