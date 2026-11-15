//
//  VXGate.swift
//  Sube el techo de la tabla de versiones y reporta el resultado.
//

import Darwin
import MachO
import Foundation

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
        for n in needles {
            for c in [n, "_" + n] {
                if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), c) {
                    out.append((c, p, 0))
                }
            }
        }
        return out
    }

    private static func sweep() -> (Int, Int, String) {
        guard let hdr = _dyld_get_image_header(0), hdr.pointee.magic == MH_MAGIC_64 else { return (0, 0, "") }
        let base = UnsafeRawPointer(hdr)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)

        var textVm: UInt = 0
        var found = false
        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                if segName(seg) == "__TEXT" { textVm = UInt(seg.pointee.vmaddr); found = true }
            }
            guard cmd.pointee.cmdsize > 0 else { break }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }
        guard found else { return (0, 0, "") }

        cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)
        let prot = VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE | VM_PROT_COPY
        var total = 0
        var denied = 0
        var segs: [String] = []

        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                let n = segName(seg)
                let size = Int(seg.pointee.filesize)
                if size > 8, size < 200_000_000, n != "__PAGEZERO" {
                    let start = UInt(bitPattern: base) &+ (UInt(seg.pointee.vmaddr) &- textVm)
                    if let raw = UnsafeMutableRawPointer(bitPattern: start) {
                        let b = raw.assumingMemoryBound(to: UInt8.self)
                        var hit = 0
                        var p = 0
                        while p * 0x1000 < size {
                            let pg = start &+ UInt(p) * 0x1000
                            if vm_protect(mach_task_self_, vm_address_t(pg), vm_size_t(0x1000),
                                          boolean_t(0), prot) == KERN_SUCCESS {
                                let from = p * 0x1000
                                let to = min(from + 0x1000, size)
                                var i = from
                                while i + 4 < to {
                                    if b[i] == 0x32, b[i + 1] == 0x37, b[i + 2] == 0x2E, b[i + 3] == 0x32 {
                                        let next = b[i + 4]
                                        if next == 0x20 || next == 0x29 || next == 0x00 {
                                            b[i + 3] = 0x33
                                            hit += 1
                                            i += 5
                                            continue
                                        }
                                    }
                                    i += 1
                                }
                            } else {
                                denied += 1
                            }
                            p += 1
                        }
                        if hit > 0 { icache?(UnsafeRawPointer(raw), size) }
                        segs.append("\(n)=\(hit)")
                        total += hit
                    }
                }
            }
            guard cmd.pointee.cmdsize > 0 else { break }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }
        return (total, denied, segs.joined(separator: " "))
    }

    static func install() {
        let (n, d, s) = sweep()
        let txt = "seg \(n) · neg \(d) · \(s)"
        log("vx: gate " + txt)
        UserDefaults.standard.set(txt, forKey: "vx.diag")
    }
}

@_cdecl("VXGateInstall")
public func VXGateInstall() {
    VXGate.install()
}
