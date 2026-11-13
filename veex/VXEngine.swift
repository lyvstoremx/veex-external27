import SwiftUI
import Security

enum VXEngine {
    static let handle = UnsafeMutableRawPointer(bitPattern: -2)

    static let symbols = [
        "bad_query",
        "bad_query_list",
        "bad_query_release",
        "MCMActivateContainerPath",
        "afc_client_connect_rsd",
        "file_service_connect_rsd"
    ]

    static func resolve() -> [(String, Bool)] {
        symbols.map { ($0, dlsym(handle, $0) != nil) }
    }

    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        guard let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static func containerPath(_ bundle: String) -> String? {
        typealias F = @convention(c) (Int32, UnsafePointer<CChar>, Bool, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> UnsafeMutablePointer<CChar>?
        guard let f = sym("MCMActivateContainerPath", F.self) else { return nil }
        var err: UnsafeMutablePointer<CChar>? = nil
        guard let r = f(2, bundle, false, &err), r.pointee != 0 else { return nil }
        return String(cString: r)
    }

    static func grant(_ path: String) -> Int64 {
        typealias F = @convention(c) (UnsafeMutablePointer<CChar>, Bool, UnsafePointer<CChar>?, Bool) -> Int64
        guard let f = sym("bad_query", F.self) else { return -1 }
        return f(strdup(path)!, true, nil, false)
    }

    static func release(_ h: Int64) {
        typealias F = @convention(c) (Int64) -> Void
        guard let f = sym("bad_query_release", F.self) else { return }
        f(h)
    }

    static func list(_ path: String) -> [String] {
        typealias F = @convention(c) (UnsafeMutablePointer<CChar>, Int64) -> UnsafeMutablePointer<CChar>?
        guard let f = sym("bad_query_list", F.self),
              let r = f(strdup(path)!, 4_000_000) else { return [] }
        defer { free(r) }
        return String(cString: r).split(separator: "\n").map(String.init)
    }

    static func probe(_ bundle: String) -> [String] {
        var out: [String] = []
        guard let p = containerPath(bundle) else { return ["sin ruta · \(bundle)"] }
        out.append("ruta: \(p)")
        let h = grant(p)
        out.append("grant: \(h)")
        if h >= 0 { release(h) }
        let items = list(p)
        out.append("items: \(items.count)")
        out.append(contentsOf: items.prefix(30))
        return out
    }

    static func prefs() -> [String] {
        let p = NSHomeDirectory() + "/Library/Preferences/com.apple.mobile.MobileHouseArrest.plist"
        guard let d = FileManager.default.contents(atPath: p),
              let obj = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any]
        else { return ["sin plist o sin acceso"] }
        return obj.keys.sorted().map { k in
            let v = obj[k]
            if let s = v as? String { return "\(k) = texto \(s.count)" }
            if let x = v as? Data { return "» \(k) = datos \(x.count)" }
            if let n = v as? Int { return "\(k) = num \(n)" }
            return "\(k) = otro"
        }
    }

    private static func keychain(_ service: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return "\(d.count) B"
    }

    static func pairing() -> String? { keychain("3105-airlift-pairing-v1") }
    static func pin() -> String? { keychain("3105-airlift-pairing-v1-pin") }

    static func dump() -> [String] {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let arr = out as? [[String: Any]] else { return [] }
        var seen: [String] = []
        for d in arr {
            let s = (d[kSecAttrService as String] as? String) ?? "?"
            let a = (d[kSecAttrAccount as String] as? String) ?? ""
            let line = a.isEmpty ? s : "\(s) · \(a)"
            if !seen.contains(line) { seen.append(line) }
        }
        return seen
    }

    static func findPairing() -> [String] {
        var out: [String] = []
        let home = NSHomeDirectory()
        guard let e = FileManager.default.enumerator(
            at: URL(fileURLWithPath: home),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return ["sin acceso"] }
        var n = 0
        for case let u as URL in e {
            n += 1
            if n > 9000 { break }
            let low = u.lastPathComponent.lowercased()
            let short = u.path.replacingOccurrences(of: home, with: "~")
            if low.contains("pair") || low.contains("rpp") {
                out.append("» " + short)
                continue
            }
            guard let h = try? FileHandle(forReadingFrom: u),
                  let d = try? h.read(upToCount: 12),
                  let s = String(data: d, encoding: .ascii) else { continue }
            try? h.close()
            if s.contains("RPPairing") { out.append("MAGIC » " + short) }
        }
        out.append("revisados: \(n)")
        return out
    }
}

struct VXEngineCard: View {
    @State private var syms: [(String, Bool)] = []
    @State private var items: [String] = []
    @State private var bundle = ""
    @State private var ran = false
    @State private var listed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text("MOTOR")
                    .font(.system(size: 9, weight: .black))
                    .tracking(2)
                    .foregroundStyle(VX.red)
                Spacer()
                Button {
                    syms = VXEngine.resolve()
                    ran = true
                } label: {
                    Text("DIAGNÓSTICO")
                        .font(.system(size: 7, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 7)
                        .background(VX.red)
                }
                Button {
                    items = VXEngine.probe(bundle.trimmingCharacters(in: .whitespaces))
                    listed = true
                } label: {
                    Text("PROBAR")
                        .font(.system(size: 7, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 7)
                        .background(VX.slab)
                        .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                }
                Button {
                    items = VXEngine.findPairing()
                    listed = true
                } label: {
                    Text("ARCHIVOS")
                        .font(.system(size: 7, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 7)
                        .background(VX.slab)
                        .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                }
                Button {
                    items = VXEngine.prefs()
                    listed = true
                } label: {
                    Text("PREFS")
                        .font(.system(size: 7, weight: .black))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 7)
                        .background(VX.slab)
                        .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                }
            }

            TextField("bundle id del juego", text: $bundle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(VX.paper)
                .padding(.vertical, 8)
                .padding(.horizontal, 9)
                .background(Color.black.opacity(0.5))
                .overlay(Rectangle().stroke(VX.line, lineWidth: 1))

            if ran {
                ForEach(syms, id: \.0) { name, ok in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(ok ? VX.green : VX.red)
                            .frame(width: 5, height: 5)
                        Text(name)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ok ? VX.paper : VX.dim)
                            .lineLimit(1)
                    }
                }
                Rectangle().fill(VX.line).frame(height: 1).padding(.vertical, 2)
                line("PAIRING", VXEngine.pairing())
                line("PIN", VXEngine.pin())
                Text("verde = símbolo disponible · rojo = falta")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(VX.dim)
            }

            if listed {
                Rectangle().fill(VX.line).frame(height: 1).padding(.vertical, 2)
                Text("SALIDA · \(items.count)")
                    .font(.system(size: 8, weight: .black))
                    .tracking(2)
                    .foregroundStyle(VX.dim)
                if items.isEmpty {
                    Text("vacío")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(VX.red)
                } else {
                    ForEach(items, id: \.self) { i in
                        Text(i)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(VX.paper)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .vxCard(Color(white: 0.10))
    }

    private func line(_ t: String, _ v: String?) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(v == nil ? VX.red : VX.green)
                .frame(width: 5, height: 5)
            Text(t)
                .font(.system(size: 8, weight: .black))
                .tracking(2)
                .foregroundStyle(VX.dim)
            Spacer()
            Text(v ?? "no encontrado")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(v == nil ? VX.red : VX.paper)
                .lineLimit(1)
        }
    }
}
