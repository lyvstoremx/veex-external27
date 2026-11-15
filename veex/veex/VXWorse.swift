//
//  VXWorse.swift
//  Ruta de contenedores para iOS 27+. Solo se invoca si MCM falla.
//

import Foundation
import Darwin

enum VXWorse {
    private typealias S1 = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    private typealias S2 = @convention(c) (UnsafePointer<CChar>, Int64) -> UnsafeMutablePointer<CChar>?
    private typealias H1 = @convention(c) (UnsafePointer<CChar>) -> Int64
    private typealias H2 = @convention(c) (UnsafePointer<CChar>, Int64) -> Int64
    private typealias H3 = @convention(c) (UnsafePointer<CChar>, Int64, Int64) -> Int64

    private static func pick() -> UnsafeMutableRawPointer? {
        let hits = VXGate.locate(["worse"])
        if let exact = hits.first(where: { $0.0.hasSuffix("worse_query") }) { return exact.1 }
        return hits.first?.1
    }

    static var present: Bool { pick() != nil }

    private static func fn<T>(_ t: T.Type) -> T? {
        guard let p = pick() else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static func str(_ p: UnsafeMutablePointer<CChar>?) -> String? {
        guard let p else { return nil }
        var s = String(cString: p)
        if s == "/var" || s.hasPrefix("/var/") { s = "/private" + s }
        return s.hasPrefix("/") ? s : nil
    }

    static func path(_ bundle: String) -> String? {
        guard present else { log("vx: sin símbolo worse"); return nil }
        let c = strdup(bundle)!
        defer { free(c) }

        log("vx: worse_query(path) s1")
        if let f: S1 = fn(S1.self), let s = str(f(c)) {
            log("vx: worse_query s1 → \(s)")
            return s
        }
        for part in [Int64(0), 3, 1] {
            log("vx: worse_query(path) s2 p\(part)")
            if let f: S2 = fn(S2.self), let s = str(f(c, part)) {
                log("vx: worse_query s2-p\(part) → \(s)")
                return s
            }
        }
        log("vx: worse_query sin ruta")
        return nil
    }

    static func grant(_ path: String) -> Int64 {
        log("vx: pairing \(VXEngine.pairing() ?? "no")")
        log("vx: pin \(VXEngine.pin() ?? "no")")
        for l in VXEngine.findPairing().prefix(12) { log("vx: par \(l)") }

        guard present else { log("vx: sin símbolo worse"); return -1 }
        let c = strdup(path)!
        defer { free(c) }

        func ok(_ h: Int64, _ label: String) -> Int64? {
            Thread.sleep(forTimeInterval: 0.06)
            let w = VXContainers.writeTest(path)
            log("vx: worse \(label) → \(h) · escritura \(w)")
            if w == "ok" { return h }
            if h > 1 { VXMCM.release(h) }
            return nil
        }

        if let f: H1 = fn(H1.self), let h = ok(f(c), "h1") { return h }
        for part in [Int64(0), 3, 1] {
            if let f: H2 = fn(H2.self), let h = ok(f(c, part), "h2-p\(part)") { return h }
        }
        for flags in [Int64(0x8000000000), 0x900000000, 0x100000000] {
            if let f: H2 = fn(H2.self), let h = ok(f(c, flags), "h2-f\(flags)") { return h }
            if let f: H3 = fn(H3.self), let h = ok(f(c, 0, flags), "h3-f\(flags)") { return h }
        }
        return -1
    }
}
