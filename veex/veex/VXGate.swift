//
//  VXGate.swift
//  Anula ExploitSupportPolicy.isSupported, solo en la imagen principal.
//

import Darwin
import MachO

enum VXGate {
    private typealias Icache = @convention(c) (UnsafeRawPointer, Int) -> Void

    private static let icache: Icache? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "sys_icache_invalidate") else { return nil }
        return unsafeBitCast(p, to: Icache.self)
    }()

    private static func segName(_ seg: UnsafePointer<segment_command_64>) -> String {
        withUnsafeBytes(of: seg.pointee.segname) { raw -> String in
            guard let b = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: b)
        }
    }

    private static func scan(_ hdr: UnsafePointer<mach_header>, _ slide: Int, _ img: Int,
                             _ needles: [String], _ out: inout [(String, UnsafeMutableRawPointer, Int)]) {
        guard hdr.pointee.magic == MH_MAGIC_64 else { return }
        let base = UnsafeRawPointer(hdr)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)

        var leVm: UInt = 0
        var leOff: UInt = 0
        var symoff: UInt = 0
        var stroff: UInt = 0
        var nsyms = 0
        var strsize = 0
        var ok = false

        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                if segName(seg) == "__LINKEDIT" {
                    leVm = UInt(seg.pointee.vmaddr)
                    leOff = UInt(seg.pointee.fileoff)
                }
            } else if cmd.pointee.cmd == UInt32(LC_SYMTAB) {
                let st = cursor.assumingMemoryBound(to: symtab_command.self)
                symoff = UInt(st.pointee.symoff)
                stroff = UInt(st.pointee.stroff)
                nsyms = Int(st.pointee.nsyms)
                strsize = Int(st.pointee.strsize)
                ok = true
            }
            guard cmd.pointee.cmdsize > 0 else { break }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }

        guard ok, leVm != 0, nsyms > 0, strsize > 0 else { return }

        let leBase = UInt(bitPattern: base) &+ UInt(bitPattern: slide) &+ leVm &- leOff &- leVm
        guard let syms = UnsafeMutableRawPointer(bitPattern: leBase &+ symoff),
              let strs = UnsafeMutableRawPointer(bitPattern: leBase &+ stroff) else { return }
        let symPtr = syms.assumingMemoryBound(to: nlist_64.self)
        let strPtr = strs.assumingMemoryBound(to: CChar.self)

        for i in 0..<nsyms {
            let s = symPtr[i]
            let idx = Int(s.n_un.n_strx)
            guard idx > 0, idx < strsize, s.n_value != 0 else { continue }
            let name = String(cString: strPtr.advanced(by: idx))
            guard needles.contains(where: { name.contains($0) }) else { continue }
            let addr = s.n_value &+ UInt64(bitPattern: Int64(slide))
            if let p = UnsafeMutableRawPointer(bitPattern: UInt(addr)) { out.append((name, p, img)) }
        }
    }

    static func locate(_ needles: [String]) -> [(String, UnsafeMutableRawPointer, Int)] {
        var out: [(String, UnsafeMutableRawPointer, Int)] = []
        for i in 0..<_dyld_image_count() {
            guard let hdr = _dyld_get_image_header(i) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(i)
            scan(hdr, slide, Int(i), needles, &out)
        }
        return out
    }

    private static func patch(_ p: UnsafeMutableRawPointer) -> Bool {
        guard UInt(bitPattern: p) % 4 == 0 else { return false }
        let w = p.assumingMemoryBound(to: UInt32.self)
        if w[0] == 0x52800020, w[1] == 0xD65F03C0 { return false }

        let page = UInt(bitPattern: p) & ~0xFFF
        let kr = vm_protect(mach_task_self_, vm_address_t(page), vm_size_t(0x4000),
                            boolean_t(0), VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)
        guard kr == KERN_SUCCESS else {
            log("vx: vm_protect \(kr)")
            return false
        }
        w[0] = 0x52800020
        w[1] = 0xD65F03C0
        icache?(UnsafeRawPointer(p), 8)
        return true
    }

    static func install() {
        let hits = locate(["SupportPolicy"]).filter { $0.2 == 0 }
        if hits.isEmpty { log("vx: gate no localizado") }
        for (n, h, _) in hits where patch(h) { log("vx: gate parcheado \(n)") }
    }
}

@_cdecl("VXGateInstall")
public func VXGateInstall() {
    VXGate.install()
}
