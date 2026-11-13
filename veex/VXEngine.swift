import SwiftUI
import Security

enum VXEngine {
    static let symbols = [
        "afc_client_connect_rsd",
        "afc_client_new_with_rsd",
        "afc_client_free",
        "file_service_connect_rsd",
        "tunnel_create_rppairing_multihost",
        "tunnel_start_tcp",
        "rsd_handshake",
        "idevice_rsd_connect"
    ]

    static func resolve() -> [(String, Bool)] {
        let h = UnsafeMutableRawPointer(bitPattern: -2)
        return symbols.map { ($0, dlsym(h, $0) != nil) }
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
}

struct VXEngineCard: View {
    @State private var syms: [(String, Bool)] = []
    @State private var pair: String?
    @State private var pin: String?
    @State private var items: [String] = []
    @State private var ran = false
    @State private var listed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
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
                        .tracking(1.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(VX.red)
                }
                Button {
                    items = VXEngine.dump()
                    listed = true
                } label: {
                    Text("ENUMERAR")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
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
                line("PAIRING", pair ?? "no encontrado")
                line("PIN", pin)
                Text("verde = símbolo disponible · rojo = falta")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(VX.dim)
            }

            if listed {
                Rectangle().fill(VX.line).frame(height: 1).padding(.vertical, 2)
                Text("KEYCHAIN · \(items.count)")
                    .font(.system(size: 8, weight: .black))
                    .tracking(2)
                    .foregroundStyle(VX.dim)
                if items.isEmpty {
                    Text("sin acceso o vacío")
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
