//
//  VXGate.swift
//  Corrige el techo de la tabla en los Localizable.strings.
//

import Darwin
import Foundation

enum VXGate {
    private static func fix(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "27.2 ", with: "27.3 ")
        t = t.replacingOccurrences(of: "27.2)", with: "27.3)")
        t = t.replacingOccurrences(of: "27.2\\n", with: "27.3\\n")
        return t
    }

    private static func uno(_ path: String) -> String {
        guard let d = FileManager.default.contents(atPath: path) else { return "falta" }

        if d.starts(with: Array("bplist00".utf8)) {
            guard var dict = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: String] else {
                return "plist ilegible"
            }
            var n = 0
            for (k, v) in dict {
                let w = fix(v)
                if w != v { dict[k] = w; n += 1 }
            }
            guard n > 0 else { return "plist 0" }
            guard let out = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) else {
                return "plist enc"
            }
            do {
                try out.write(to: URL(fileURLWithPath: path))
                return "plist ok \(n)"
            } catch {
                return "plist fallo \(errno)"
            }
        }

        var enc = String.Encoding.utf8
        var body = d
        if d.starts(with: [0xFF, 0xFE]) { enc = .utf16LittleEndian; body = d.dropFirst(2) }
        else if d.starts(with: [0xFE, 0xFF]) { enc = .utf16BigEndian; body = d.dropFirst(2) }

        let s0 = String(data: body, encoding: enc) ?? String(data: d, encoding: .utf16LittleEndian)
        guard let s0 else { return "ilegible" }
        let s1 = fix(s0)
        guard s1 != s0 else { return "0" }

        guard let out = s1.data(using: enc) ?? s1.data(using: .utf16LittleEndian) else { return "enc" }
        do {
            try out.write(to: URL(fileURLWithPath: path))
            return "ok"
        } catch {
            return "fallo \(errno)"
        }
    }

    static func install() {
        let fm = FileManager.default
        let dir = Bundle.main.bundlePath
        var partes: [String] = []

        if let items = try? fm.contentsOfDirectory(atPath: dir) {
            for it in items where it.hasSuffix(".lproj") {
                let r = uno(dir + "/" + it + "/Localizable.strings")
                partes.append("\(it):\(r)")
            }
        } else {
            partes.append("sin dir")
        }

        let txt = partes.joined(separator: " ")
        log("vx: " + txt)
        UserDefaults.standard.set(txt, forKey: "vx.diag")
    }
}

@_cdecl("VXGateInstall")
public func VXGateInstall() {
    VXGate.install()
}
