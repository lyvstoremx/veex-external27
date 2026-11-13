//
//  VXShim.swift
//  Contenedor y claves para el motor compilado en el dylib.
//  El contenedor se pide a la app con sus funciones C (MCM + bad_query).
//

import Foundation
import CryptoKit
import Darwin

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

enum VXContainers {
    private static var roots: [String: URL] = [:]
    private static var handles: [String: Int64] = [:]

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    private static func path(for bundle: String) -> String? {
        guard let raw = symbol("MCMActivateContainerPath") else { return nil }
        typealias F = @convention(c) (
            Int32, UnsafePointer<CChar>, Bool,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> UnsafeMutablePointer<CChar>?
        var err: UnsafeMutablePointer<CChar>?
        guard let r = unsafeBitCast(raw, to: F.self)(2, bundle, false, &err) else { return nil }
        return String(cString: r)
    }

    private static func grant(_ path: String) -> Int64 {
        guard let raw = symbol("bad_query") else { return -1 }
        typealias F = @convention(c) (UnsafeMutablePointer<CChar>, Bool, UnsafePointer<CChar>?, Bool) -> Int64
        return unsafeBitCast(raw, to: F.self)(strdup(path)!, true, nil, false)
    }

    static func resolve(_ bundle: String) throws -> URL {
        if let cached = roots[bundle] { return cached }
        guard let p = path(for: bundle) else {
            throw PatchPackageError.targetAppUnavailable(bundle)
        }
        let h = grant(p)
        guard h >= 0 else {
            throw PatchPackageError.targetAppUnavailable(bundle)
        }
        let url = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: p, isDirectory: true))
        handles[bundle] = h
        roots[bundle] = url
        log("vx: contenedor \(bundle) → \(p) (handle \(h))")
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
