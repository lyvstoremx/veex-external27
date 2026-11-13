import SwiftUI
import Darwin
import Security

enum VXEngine {
    static let handle = UnsafeMutableRawPointer(bitPattern: -2)

    static let symbols = [
        "afc_client_connect_rsd",
        "afc_client_new_with_rsd",
        "afc_client_free",
        "afc_file_open",
        "afc_file_write",
        "afc_file_read_entire",
        "afc_rename_path",
        "file_service_connect_rsd",
        "file_service_create_session",
        "tunnel_create_rppairing_multihost",
        "tunnel_create_usb",
        "rsd_get_services",
        "idevice_provider_connect_service_stream",
        "rp_pairing_file_read",
        "rp_pairing_file_write",
        "bad_query",
        "bad_query_list",
        "bad_query_release",
        "MCMActivateContainerPath"
    ]

    static func resolve() -> [(String, Bool)] {
        symbols.map { ($0, dlsym(handle, $0) != nil) }
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
        if let s = String(data: d, encoding: .utf8) { return "\(d.count) B · \(s.prefix(24))" }
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
              let arr = out as? [[String: Any]] else { return ["sin acceso"] }
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

    static func path(for bundle: String) -> String? {
        guard let raw = dlsym(handle, "MCMActivateContainerPath") else { return nil }
        typealias F = @convention(c) (
            Int32, UnsafePointer<CChar>, Bool,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> UnsafeMutablePointer<CChar>?
        let f = unsafeBitCast(raw, to: F.self)
        var err: UnsafeMutablePointer<CChar>?
        guard let r = f(2, bundle, false, &err) else { return nil }
        return String(cString: r)
    }

    static func grant(_ path: String) -> Int64 {
        guard let raw = dlsym(handle, "bad_query") else { return -1 }
        typealias F = @convention(c) (UnsafeMutablePointer<CChar>, Bool, UnsafePointer<CChar>?, Bool) -> Int64
        return unsafeBitCast(raw, to: F.self)(strdup(path)!, true, nil, false)
    }

    static func release(_ h: Int64) {
        guard let raw = dlsym(handle, "bad_query_release") else { return }
        typealias F = @convention(c) (Int64) -> Void
        unsafeBitCast(raw, to: F.self)(h)
    }

    static func list(_ path: String) -> [String] {
        guard let raw = dlsym(handle, "bad_query_list") else { return [] }
        typealias F = @convention(c) (UnsafeMutablePointer<CChar>, Int64) -> UnsafeMutablePointer<CChar>?
        guard let r = unsafeBitCast(raw, to: F.self)(strdup(path)!, 2_000_000) else { return [] }
        defer { free(r) }
        return String(cString: r).split(separator: "\n").map(String.init)
    }

    static func probe(bundle: String) -> [String] {
        var out: [String] = []
        guard !bundle.isEmpty else { return ["bundle vacío"] }
        guard let p = path(for: bundle) else { return ["sin ruta para \(bundle)"] }
        out.append("ruta: \(p)")
        let h = grant(p)
        out.append("grant: \(h)")
        if h >= 0 { release(h) }
        let items = list(p)
        out.append("items: \(items.count)")
        out.append(contentsOf: items.prefix(30))
        return out
    }

    static func tunnel() -> [String] {
        var out: [String] = []
        typealias F = @convention(c) (
            UnsafeMutableRawPointer, Int, UnsafePointer<CChar>, UnsafeRawPointer?,
            Int, Int, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
        ) -> Int32
        guard let raw = dlsym(handle, "tunnel_create_rppairing_multihost") else { return ["sin símbolo"] }
        let f = unsafeBitCast(raw, to: F.self)
        let host = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        let extra = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { host.deallocate(); extra.deallocate() }
        memset(host, 0, 64)
        memset(extra, 0, 64)
        let rc = f(host, 16, "airlift-mini", nil, 0, 0, nil, nil, extra, extra, extra)
        out.append("rc: \(rc)")
        let h = String(cString: host.assumingMemoryBound(to: CChar.self))
        out.append("host: \(h.isEmpty ? "-" : h)")
        return out
    }
}

struct VXEngineCard: View {
    @State private var syms: [(String, Bool)] = []
    @State private var pair: String?
    @State private var pin: String?
    @State private var ran = false
    @State private var items: [String] = []
    @State private var listed = false
    @State private var bundle = ""
    @State private var out: [String] = []
    @State private var tun: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("MOTOR")
                    .font(.system(size: 9, weight: .black))
                    .tracking(3)
                    .foregroundStyle(VX.red)
                Spacer()
                Button {
                    syms = VXEngine.resolve()
                    pair = VXEngine.pairing()
                    pin = VXEngine.pin()
                    ran = true
                } label: {
                    Text("DIAGNÓSTICO")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(VX.red)
                }
                Button {
                    items = VXEngine.dump()
                    listed = true
                } label: {
                    Text("ENUMERAR")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(VX.slab)
                        .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                }
            }

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
                row("PAIRING", pair)
                row("PIN", pin)
            }

            if listed {
                ForEach(items.indices, id: \.self) { i in
                    Text(items[i])
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(VX.dim)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                TextField("bundle id", text: $bundle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VX.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black)
                    .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                Button {
                    out = VXEngine.probe(bundle: bundle)
                } label: {
                    Text("PROBAR")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(VX.slab)
                        .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                }
                Button {
                    tun = VXEngine.tunnel()
                } label: {
                    Text("TUNEL")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(VX.red)
                }
            }

            ForEach(out.indices, id: \.self) { i in
                Text(out[i])
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(VX.dim)
                    .lineLimit(1)
            }

            ForEach(tun.indices, id: \.self) { i in
                Text(tun[i])
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(i == 0 ? VX.red : VX.paper)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(VX.slab)
        .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
    }

    private func row(_ k: String, _ v: String?) -> some View {
        HStack(spacing: 8) {
            Text(k)
                .font(.system(size: 8, weight: .black))
                .tracking(1.6)
                .foregroundStyle(VX.dim)
            Spacer()
            Text(v ?? "no encontrado")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(v == nil ? VX.red : VX.paper)
                .lineLimit(1)
        }
    }
}
