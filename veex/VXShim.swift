//
//  VXShim.swift
//  Contenedores y claves. El permiso se resuelve por intentos y se verifica escribiendo.
//

import Foundation
import CryptoKit
import Darwin
import MachO

func log(_ msg: String) {
    guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
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
        if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { return p }
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
                    let addr = s.n_value &+ UInt64(bitPattern: Int64(slide))
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

enum VXMCM {
    private typealias Create = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias SetU64 = @convention(c) (UnsafeMutableRawPointer, UInt64) -> Void
    private typealias SetXPC = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void
    private typealias SetDomain = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void
    private typealias GetPtr = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias GetStr = @convention(c) (UnsafeMutableRawPointer) -> UnsafePointer<CChar>?
    private typealias GetInt = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias CopyToken = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>?
    private typealias Activate = @convention(c) (UnsafeMutableRawPointer, Bool) -> Bool
    private typealias FreeFn = @convention(c) (UnsafeMutableRawPointer) -> Void
    private typealias XpcStr = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    private typealias Consume = @convention(c) (UnsafePointer<CChar>) -> Int64
    private typealias Release = @convention(c) (Int64) -> Int32

    private static let lib: UnsafeMutableRawPointer? = dlopen(
        "/usr/lib/system/libsystem_containermanager.dylib",
        RTLD_NOW | RTLD_LOCAL
    )

    private static var keep: [UnsafeMutableRawPointer] = []
    private static var best: (cls: UInt64, part: UInt64, flags: UInt64, group: Bool, domain: Bool)?

    private static func sym<T>(_ name: String) -> T? {
        guard let lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static func def<T>(_ name: String) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static var available: Bool {
        let f: Create? = sym("container_query_create")
        return lib != nil && f != nil
    }

    private static func detail(_ q: UnsafeMutableRawPointer) -> String {
        guard let getErr: GetPtr = sym("container_query_get_last_error") else { return "sin detalle" }
        guard let err = getErr(q) else { return "sin error" }
        let posix: Int32 = {
            guard let f: GetInt = sym("container_error_get_posix_errno") else { return 0 }
            return f(err)
        }()
        let msg: String = {
            guard let f: GetStr = sym("container_error_get_message"),
                  let raw = f(err) else { return "?" }
            return String(cString: raw)
        }()
        return "posix \(posix) · \(msg)"
    }

    private static func build(
        cls: UInt64,
        identifier: String,
        group: Bool,
        flags: UInt64,
        part: UInt64,
        domain: String?
    ) -> UnsafeMutableRawPointer? {
        guard let create: Create = sym("container_query_create"),
              let setClass: SetU64 = sym("container_query_set_class"),
              let setFlags: SetU64 = sym("container_query_operation_set_flags") else { return nil }
        guard let q = create() else { return nil }

        setClass(q, cls)
        if let setIds: SetXPC = sym(group
            ? "container_query_set_group_identifiers"
            : "container_query_set_identifiers"),
           let xpcStr: XpcStr = def("xpc_string_create"),
           let ids = xpcStr(identifier) {
            setIds(q, ids)
        }
        if let setPart: SetU64 = sym("container_query_operation_set_part") { setPart(q, part) }
        if let domain, let setDomain: SetDomain = sym("container_query_operation_set_part_domain") {
            setDomain(q, domain)
        }
        setFlags(q, flags)
        return q
    }

    static func path(_ bundle: String) -> String? {
        guard let q = build(cls: 2, identifier: bundle, group: false, flags: 0x100000000, part: 0, domain: nil),
              let getSingle: GetPtr = sym("container_query_get_single_result"),
              let getPath: GetStr = sym("container_object_get_path"),
              let freeQ: FreeFn = sym("container_query_free") else { return nil }
        defer { freeQ(q) }

        guard let obj = getSingle(q), let raw = getPath(obj) else { return nil }
        var p = String(cString: raw)
        if p == "/var" || p.hasPrefix("/var/") { p = "/private" + p }
        return p
    }

    private static func attempt(
        label: String,
        cls: UInt64,
        identifier: String,
        group: Bool,
        flags: UInt64,
        part: UInt64,
        domain: String?
    ) -> Int64 {
        guard let q = build(cls: cls, identifier: identifier, group: group, flags: flags, part: part, domain: domain),
              let getSingle: GetPtr = sym("container_query_get_single_result") else {
            log("vx: \(label) sin consulta")
            return -1
        }
        guard let obj = getSingle(q) else {
            log("vx: \(label) daemon sin resultado · \(detail(q))")
            return -1
        }

        if let copyToken: CopyToken = sym("container_copy_sandbox_token"),
           let consume: Consume = def("sandbox_extension_consume"),
           let token = copyToken(obj) {
            let h = consume(token)
            free(token)
            log("vx: \(label) consume = \(h)")
            if h >= 0 {
                keep.append(q)
                return h
            }
        } else {
            log("vx: \(label) sin token o sin consume")
        }

        if let copy: GetPtr = sym("container_object_copy"),
           let activate: Activate = sym("container_object_sandbox_extension_activate"),
           let copyObj = copy(obj) {
            let ok = activate(copyObj, false)
            log("vx: \(label) activate = \(ok)")
            if ok {
                keep.append(copyObj)
                keep.append(q)
                return 1
            }
        } else {
            log("vx: \(label) sin activate")
        }

        return -1
    }

    private static func domain(_ path: String) -> String {
        let depth = Bundle.main.bundlePath.split(separator: "/").count
        let n = max(9, depth + 2)
        return Array(repeating: "..", count: n).joined(separator: "/") + path
    }

    static func grant(_ path: String, bundle: String = "") -> Int64 {
        let dom = domain(path)
        let gestalt = "systemgroup.com.apple.mobilegestaltcache"

        var tries: [(String, UInt64, String, Bool, UInt64, UInt64, String?)] = []

        if let b = best {
            tries.append(("mejor", b.cls, b.group ? gestalt : bundle, b.group, b.flags, b.part, b.domain ? dom : nil))
        }

        for part in [UInt64(3), 1, 2, 0] {
            for flags in [UInt64(0x900000000), 0x8000000000, 0x100000000, 0x300000000] {
                tries.append(("gestalt-a-p\(part)-f\(flags)", 13, gestalt, true, flags, part, dom))
                tries.append(("gestalt-c-p\(part)-f\(flags)", 13, gestalt, true, flags, part, dom))
            }
        }

        if !bundle.isEmpty {
            for part in [UInt64(0), 3, 1, 2] {
                for flags in [UInt64(0x900000000), 0x100000000, 0x8000000000] {
                    tries.append(("bundle-a-p\(part)-f\(flags)", 2, bundle, false, flags, part, nil))
                    tries.append(("bundle-c-p\(part)-f\(flags)", 2, bundle, false, flags, part, nil))
                }
            }
        }

        var n = 0
        for t in tries {
            n += 1
            if n > 60 { break }
            let h = attempt(label: t.0, cls: t.1, identifier: t.2, group: t.3, flags: t.4, part: t.5, domain: t.6)
            guard h >= 0 else { continue }
            if VXContainers.writeTest(path) == "ok" {
                best = (t.1, t.5, t.4, t.3, t.6 != nil)
                log("vx: combinación ganadora \(t.0)")
                return h
            }
            log("vx: \(t.0) concedió pero no escribe")
            release(h)
        }

        log("vx: sin combinación para \(path)")
        return -1
    }

    static func release(_ handle: Int64) {
        guard handle > 1, let f: Release = def("sandbox_extension_release") else { return }
        _ = f(handle)
    }
}

enum VXContainers {
    private static var roots: [String: URL] = [:]

    static func writeTest(_ path: String) -> String {
        let file = path + "/.veex-probe"
        if FileManager.default.createFile(atPath: file, contents: Data("x".utf8)) {
            try? FileManager.default.removeItem(atPath: file)
            return "ok"
        }
        return "errno \(errno)"
    }

    static func resolve(_ bundle: String) throws -> URL {
        if let cached = roots[bundle] { return cached }

        guard VXMCM.available else {
            log("vx: containermanager no disponible")
            throw PatchPackageError.targetAppUnavailable(bundle)
        }
        guard let path = VXMCM.path(bundle) else {
            log("vx: sin ruta para \(bundle)")
            throw PatchPackageError.targetAppUnavailable(bundle)
        }

        let url = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))

        if writeTest(path) == "ok" {
            roots[bundle] = url
            log("vx: \(bundle) escribible sin extensión")
            return url
        }

        let handle = VXMCM.grant(path, bundle: bundle)
        let check = writeTest(path)
        log("vx: \(bundle) → \(path) · grant \(handle) · escritura \(check)")

        guard check == "ok" else {
            throw PatchPackageError.targetAppUnavailable(bundle)
        }

        roots[bundle] = url
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
