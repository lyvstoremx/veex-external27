//
//  VXGate.swift
//  Sube el techo de la tabla de versiones en las cadenas del binario.
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

    private static func patchVersion() -> Int {
        guard let hdr = _dyld_get_image_header(0), hdr.pointee.magic == MH_MAGIC_64 else { return 0 }
        let slide = _dyld_get_image_vmaddr_slide(0)
        let base = UnsafeRawPointer(hdr)
        var cursor = base.advanced(by: MemoryLayout<mach_header_64>.size)
        var total = 0

        for _ in 0..<Int(hdr.pointee.ncmds) {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == UInt32(LC_SEGMENT_64) {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                if segName(seg) == "__cstring" {
                    let size = Int(seg.pointee.filesize)
                    guard size > 8, size < 8_000_000 else { break }
                    let start = UInt(bitPattern: base) &+ UInt(bitPattern: slide) &+ UInt(seg.pointee.vmaddr)
                    guard let raw = UnsafeMutableRawPointer(bitPattern: start) else { break }
                    let page = start & ~0xFFF
                    _ = vm_protect(mach_task_self_, vm_address_t(page),
                                   vm_size_t(size + 0x4000), boolean_t(0),
                                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)
                    let b = raw.assumingMemoryBound(to: UInt8.self)
                    var i = 0
                    while i + 3 < size {
                        if b[i] == 0x32, b[i + 1] == 0x37, b[i + 2] == 0x2E, b[i + 3] == 0x32 {
                            b[i + 3] = 0x33
                            total += 1
                            i += 4
                            continue
                        }
                        i += 1
                    }
                    icache?(UnsafeRawPointer(raw), size)
                    break
                }
            }
            guard cmd.pointee.cmdsize > 0 else { break }
            cursor = cursor.advanced(by: Int(cmd.pointee.cmdsize))
        }
        return total
    }

    static func install() {
        log("vx: gate inicio")
        let n = patchVersion()
        log("vx: gate version parches \(n)")
    }
}

@_cdecl("VXGateInstall")
public func VXGateInstall() {
    VXGate.install()
}
