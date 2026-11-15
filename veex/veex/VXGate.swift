//
//  VXGate.swift
//  Sube el techo de la tabla de versiones en todos los segmentos.
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

    static func locate(_ needles: [String]) -> [(String, UnsafeMutableRawPointer, Int)] {
        var out: [(String, UnsafeMutableRawPointer, Int)] = []
        guard let hdr = _dyld_get_image_header(0), hdr.pointee.magic == MH_MAGIC_64 else { return out }

        let slide = _dyld_get_image_vmaddr_slide(0)
        let base = UnsafeRawPointer(hdr)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)

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
                if segName(seg) == "__LINKEDIT" { leOff = UInt(seg.pointee.fileoff) }
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

        guard ok, nsyms > 0, strsize > 0 else { return out }

        let leBase = UInt(bitPattern: base) &+ UInt(bitPattern: slide) &- leOff
        guard let syms = UnsafeMutableRawPointer(bitPattern: leBase &+ symoff),
              let strs = UnsafeMutableRawPointer(bitPattern: leBase &+ stroff) else { return out }
        let symPtr = syms.assumingMemoryBound(to: nlist_64.self)
        let strPtr = strs.assumingMemoryBound(to: CChar.self)

        for i in 0..<nsyms {
            let s = symPtr[i]
            let idx = Int(s.n_un.n_strx)
            guard idx > 0, idx < strsize, s.n_value != 0 else { continue }
            let name = String(cString: strPtr.advanced(by: idx))
            guard needles.contains(where: { name.contains($0) }) else { continue }
            let addr = s.n_value &+ UInt64(bitPattern: Int64(slide))
            if let p = UnsafeMutableRawPointer(bitPattern: UInt(addr)) { out.append((name, p, 0)) }
        }
        return out
    }

    private static func barrido(_ raw: UnsafeMutableRawPointer, _ size: Int) -> Int {
        let start = UInt(bitPattern: raw)
        let prot = VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE
        var patched = 0
        var p = 0
        while p * 0x1000 < size {
            let pg = start &+ UInt(p) * 0x1000
            if vm_protect(mach_task_self_, vm_address_t(pg), vm_size_t(0x1000),
                          boolean_t(0), prot) == KERN_SUCCESS {
                let from = p * 0x1000
                let to = min(from + 0x1000, size)
                let b = raw.assumingMemoryBound(to: UInt8.self)
                var i = from
                while i + 4 < to {
                    if b[i] == 0x32, b[i + 1] == 0x37, b[i + 2] == 0x2E, b[i + 3] == 0x32 {
                        let next = b[i + 4]
                        if next == 0x20 || next == 0x29 || next == 0x00 {
                            b[i + 3] = 0x33
                            patched += 1
                            i += 5
                            continue
                        }
                    }
                    i += 1
                }
            }
            p += 1
        }
        if patched > 0 { icache?(UnsafeRawPointer(raw), size) }
        return patched
    }

    static func install() {
        log("vx: gate inicio")
        guard let hdr = _dyld_get_image_header(0), hdr.pointee.magic == MH_MAGIC_64 else { return }
        let base = UnsafeRawPointer(hdr)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)
        var total = 0

        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                let n = segName(seg)
                let size = Int(seg.pointee.filesize)
                if size > 8, size < 80_000_000, n != "__PAGEZERO" {
                    if let raw = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: base) &+ UInt(seg.pointee.vmaddr) &- UInt(seg.pointee.vmaddr)) {
                        let r = barrido(raw.advanced(by: Int(seg.pointee.vmaddr)), size)
                        log("vx: seg \(n) \(size) → \(r)")
                        total += r
                    }
                }
            }
            guard cmd.pointee.cmdsize > 0 else { break }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }

        log("vx: gate parches \(total)")
        log("vx: gate supportpolicy \(locate(["SupportPolicy"]).count)")
    }
}

@_cdecl("VXGateInstall")
public func VXGateInstall() {
    VXGate.install()
}
