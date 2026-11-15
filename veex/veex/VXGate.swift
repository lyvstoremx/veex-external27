//
//  VXGate.swift
//  Sube el techo de la tabla de versiones.
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

    private static func fix(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "27.2 ", with: "27.3 ")
        t = t.replacingOccurrences(of: "27.2)", with: "27.3)")
        t = t.replacingOccurrences(of: "27.2\\n", with: "27.3\\n")
        return t
    }

    private static func stringsFiles() -> Int {
        let fm = FileManager.default
        let dir = Bundle.main.bundlePath
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return 0 }
        var done = 0

        for it in items where it.hasSuffix(".lproj") {
            let p = dir + "/" + it + "/Localizable.strings"
            guard let d = fm.contents(atPath: p) else { continue }

            var enc = String.Encoding.utf8
            if d.count > 1, d[0] == 0xFF, d[1] == 0xFE { enc = .utf16LittleEndian }
            else if d.count > 1, d[0] == 0xFE, d[1] == 0xFF { enc = .utf16BigEndian }

            guard let s0 = String(data: d, encoding: enc) else {
                log("vx: strings \(it) ilegible")
                continue
            }
            let s1 = fix(s0)
            guard s1 != s0 else {
                log("vx: strings \(it) sin cambios")
                continue
            }
            if let out = s1.data(using: enc) {
                do {
                    try out.write(to: URL(fileURLWithPath: p))
                    done += 1
                    log("vx: strings \(it) reescrito")
                } catch {
                    log("vx: strings \(it) fallo \(errno)")
                }
            }
        }
        return done
    }

    private static func sweep() -> Int {
        guard let hdr = _dyld_get_image_header(0), hdr.pointee.magic == MH_MAGIC_64 else { return 0 }
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
        guard found else { return 0 }

        cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)
        let prot = VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE
        var total = 0

        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                let n = segName(seg)
                let size = Int(seg.pointee.filesize)
                if size > 8, size < 80_000_000, n != "__PAGEZERO", n != "__LINKEDIT" {
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
                            }
                            p += 1
                        }
                        if hit > 0 { icache?(UnsafeRawPointer(raw), size) }
                        log("vx: seg \(n) \(size) → \(hit)")
                        total += hit
                    }
                }
            }
            guard cmd.pointee.cmdsize > 0 else { break }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }
        return total
    }

    static func install() {
        log("vx: gate inicio")
        let f = stringsFiles()
        log("vx: gate archivos \(f)")
        log("vx: gate parches \(sweep())")
    }
}

@_cdecl("VXGateInstall")
public func VXGateInstall() {
    VXGate.install()
}
