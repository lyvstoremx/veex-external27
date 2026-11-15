//
//  VXGate.swift
//  Engancha MobileGestalt para reportar 27.2.
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
    private static func segName(_ seg: UnsafePointer<segment_command_64>) -> String {
        withUnsafeBytes(of: seg.pointee.segname) { raw -> String in
            guard let b = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: b)
        }
    }

    private static func hook(_ name: String, _ repl: UnsafeMutableRawPointer) -> Int {
        guard let hdr = _dyld_get_image_header(0), hdr.pointee.magic == MH_MAGIC_64 else { return 0 }
        let base = UnsafeRawPointer(hdr)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)

        var textVm: UInt = 0
        var symoff = 0, stroff = 0, nsyms = 0, strsize = 0
        var indOff = 0, nind = 0
        var ok = false

        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                if segName(seg) == "__TEXT" { textVm = UInt(seg.pointee.vmaddr) }
            } else if cmd.pointee.cmd == UInt32(LC_SYMTAB) {
                let st = cursor.assumingMemoryBound(to: symtab_command.self)
                symoff = Int(st.pointee.symoff)
                stroff = Int(st.pointee.stroff)
                nsyms = Int(st.pointee.nsyms)
                strsize = Int(st.pointee.strsize)
                ok = true
            } else if cmd.pointee.cmd == UInt32(LC_DYSYMTAB) {
                let dy = cursor.assumingMemoryBound(to: dysymtab_command.self)
                indOff = Int(dy.pointee.indirectsymoff)
                nind = Int(dy.pointee.nindirectsyms)
            }
            guard cmd.pointee.cmdsize > 0 else { break }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }
        guard ok, nind > 0, nsyms > 0 else { return 0 }

        let syms = base.advanced(by: symoff).assumingMemoryBound(to: nlist_64.self)
        let strs = base.advanced(by: stroff).assumingMemoryBound(to: CChar.self)
        let ind = base.advanced(by: indOff).assumingMemoryBound(to: UInt32.self)

        cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)
        var hits = 0

        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                let sects = UnsafeRawPointer(seg).advanced(by: MemoryLayout<segment_command_64>.size)
                    .assumingMemoryBound(to: section_64.self)
                for j in 0..<Int(seg.pointee.nsects) {
                    let s = sects[j]
                    let flags = s.flags & 0xFF
                    guard flags == 0x7 || flags == 0x6 else { continue }
                    let start = UInt(bitPattern: base) &+ (UInt(s.addr) &- textVm)
                    let count = Int(s.size) / 8
                    guard let table = UnsafeMutableRawPointer(bitPattern: start) else { continue }
                    _ = vm_protect(mach_task_self_, vm_address_t(start & ~0xFFF),
                                   vm_size_t(0x4000), boolean_t(0),
                                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)
                    let slots = table.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
                    for k in 0..<count {
                        let idx = Int(ind[Int(s.reserved1) + k])
                        guard idx < nsyms, idx > 0 else { continue }
                        let n = syms[idx]
                        let si = Int(n.n_un.n_strx)
                        guard si > 0, si < strsize else { continue }
                        let nm = String(cString: strs.advanced(by: si))
                        guard nm == name || nm == "_" + name else { continue }
                        slots[k] = repl
                        hits += 1
                    }
                }
            }
            guard cmd.pointee.cmdsize > 0 else { break }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }
        return hits
    }

    static func install() {
        if let a = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "MGGetStringAnswer") {
            vxOrigStr = unsafeBitCast(a, to: MGStr.self)
        }
        if let b = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "MGCopyAnswer") {
            vxOrigCopy = unsafeBitCast(b, to: MGCopy.self)
        }

        var n = 0
        n += hook("MGGetStringAnswer", unsafeBitCast(vxMGStr as MGStr, to: UnsafeMutableRawPointer.self))
        n += hook("MGCopyAnswer", unsafeBitCast(vxMGCopy as MGCopy, to: UnsafeMutableRawPointer.self))

        let txt = "hook MG \(n)"
        log("vx: " + txt)
        UserDefaults.standard.set(txt, forKey: "vx.diag")
    }
}

@_cdecl("VXGateInstall")
public func VXGateInstall() {
    VXGate.install()
}
