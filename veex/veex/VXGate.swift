//
//  VXGate.swift
//  Parchea MobileGestalt para reportar 27.2.
//

import Darwin
import Foundation
import MachO

private typealias MGStr = @convention(c) (CFString?) -> Unmanaged<CFString>?
private typealias MGCopy = @convention(c) (CFString?) -> Unmanaged<CFTypeRef>?

private var vxOrigStr: MGStr?
private var vxOrigCopy: MGCopy?

private func vxReply(_ key: CFString?) -> CFString? {
    guard let key else { return nil }
    let k = key as String
    if k == "ProductVersion" || k == "ProductVersionExtra" { return "27.2" as CFString }
    return nil
}

@_cdecl("vxMGStr")
public func vxMGStr(_ key: CFString?) -> Unmanaged<CFString>? {
    if let r = vxReply(key) { return Unmanaged.passRetained(r) }
    return vxOrigStr?(key)
}

@_cdecl("vxMGCopy")
public func vxMGCopy(_ key: CFString?) -> Unmanaged<CFTypeRef>? {
    if let r = vxReply(key) { return Unmanaged.passRetained(r) }
    return vxOrigCopy?(key)
}

enum VXGate {
    private static func branch(_ from: UnsafeMutableRawPointer, _ to: UnsafeMutableRawPointer) {
        let p = from.assumingMemoryBound(to: UInt32.self)
        p[0] = 0x58000050
        p[1] = 0xD61F0200
        let q = from.advanced(by: 8).assumingMemoryBound(to: UInt.self)
        q.pointee = UInt(bitPattern: to)
    }

    private static func tramp(_ fn: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        guard let mem = mmap(nil, 64, PROT_READ | PROT_WRITE | PROT_EXEC,
                             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0),
              mem != UnsafeMutableRawPointer(bitPattern: -1) else { return nil }
        memcpy(mem, fn, 16)
        branch(mem.advanced(by: 16), fn.advanced(by: 16))
        return mem
    }

    private static func patch(_ name: String, _ repl: UnsafeMutableRawPointer,
                              _ save: (UnsafeMutableRawPointer) -> Void) -> Bool {
        guard let fn = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return false }
        guard let t = tramp(fn) else { return false }
        save(t)

        let page = UInt(bitPattern: fn) & ~0xFFF
        guard vm_protect(mach_task_self_, vm_address_t(page), vm_size_t(0x4000),
                         boolean_t(0), VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE | VM_PROT_COPY) == KERN_SUCCESS else {
            return false
        }
        branch(fn, repl)
        sys_icache_invalidate(fn, 16)
        return true
    }

    static func install() {
        var n = 0
        if patch("MGGetStringAnswer",
                 unsafeBitCast(vxMGStr as MGStr, to: UnsafeMutableRawPointer.self),
                 { vxOrigStr = unsafeBitCast($0, to: MGStr.self) }) { n += 1 }
        if patch("MGCopyAnswer",
                 unsafeBitCast(vxMGCopy as MGCopy, to: UnsafeMutableRawPointer.self),
                 { vxOrigCopy = unsafeBitCast($0, to: MGCopy.self) }) { n += 1 }

        let txt = "hook MG \(n)"
        log("vx: " + txt)
        UserDefaults.standard.set(txt, forKey: "vx.diag")
    }
}

@_cdecl("VXGateInstall")
public func VXGateInstall() {
    VXGate.install()
}
