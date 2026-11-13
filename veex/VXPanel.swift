import SwiftUI
import UIKit
import AVFoundation

let VXAdmin = "VEEX-LEVI-2004"

enum VXResult {
    case permanent
    case timed(Date)
    case bad
}

struct VXKeyEntry: Decodable {
    let key: String
    let exp: String?
}

enum VXCat: String, CaseIterable, Identifiable {
    case visual = "PRUEBA VISUAL"
    case holo = "HOLOGRAMAS"
    case aimbot = "AIMBOTS"
    case extra = "EXTRAS"
    var id: String { rawValue }
}

struct VXPatch: Identifiable {
    let id: String
    let name: String
    let cat: VXCat
}

func vxIOSSupported() -> Bool {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let m = v.majorVersion, n = v.minorVersion, p = v.patchVersion
    if m == 17 { return n <= 7 }
    if m == 18 { return n < 7 || (n == 7 && p <= 10) }
    if m == 26 { return n < 7 || (n == 7 && p <= 2) }
    if m == 27 { return n < 2 || (n == 2 && p == 0) }
    return false
}

func vxIOSLabel() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}

final class VXStore: ObservableObject {
    @Published var unlocked: Bool
    @Published var cat: VXCat = .visual
    @Published var on: Set<String> = []
    @Published var mute: Bool
    @Published var patches: [VXPatch] = []
    @Published var saved: String?
    @Published var exp: Date?
    @Published var now = Date()

    private var player: AVAudioPlayer?
    private var timer: Timer?

    init() {
        let d = UserDefaults.standard
        mute = d.bool(forKey: "vx.mute")
        saved = d.string(forKey: "vx.key")
        unlocked = false
        load()

        if let k = saved {
            switch check(k) {
            case .permanent:
                unlocked = true
            case .timed(let e):
                exp = e
                unlocked = e > Date()
            case .bad:
                saved = nil
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            if let e = self.exp, e <= Date(), self.unlocked { self.unlocked = false }
        }
    }

    deinit { timer?.invalidate() }

    private func load() {
        let dir = Bundle.main.bundlePath + "/veex"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        patches = files.filter { $0.hasSuffix(".3105") }.sorted().map { f in
            let n = (f as NSString).deletingPathExtension
            return VXPatch(id: n, name: pretty(n), cat: cat(of: n))
        }
    }

    private func pretty(_ n: String) -> String {
        let l = n.lowercased()
        if l.hasPrefix("holo_personaje") { return "HOLOGRAMA PERSONAJE" }
        if l.hasPrefix("holo_armas") { return "HOLOGRAMA ARMAS" }
        if l == "aim_drag" { return "AIM DRAG" }
        if l == "aim_pecho" { return "AIM PECHO" }
        if l == "aim_drag_antena" { return "AIM DRAG ANTENA" }
        if l == "balas_magicas" { return "BALAS MÁGICAS" }
        if l.hasPrefix("reset") { return "RESET GUEST" }
        return n.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private func cat(of n: String) -> VXCat {
        let l = n.lowercased()
        if l.hasPrefix("holo_") { return .holo }
        if l.hasPrefix("aim_") || l.hasPrefix("balas") { return .aimbot }
        return .extra
    }

    func note(_ id: String) -> String? {
        let l = id.lowercased()
        if l == "balas_magicas" || l.hasPrefix("holo_armas") { return "bajo tu propio riesgo" }
        if l.hasPrefix("reset") { return "no dejar activado" }
        return nil
    }

    func check(_ raw: String) -> VXResult {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !k.isEmpty else { return .bad }
        if k == VXAdmin { return .permanent }

        guard let p = Bundle.main.path(forResource: "keys", ofType: "json", inDirectory: "veex"),
              let d = FileManager.default.contents(atPath: p),
              let list = try? JSONDecoder().decode([VXKeyEntry].self, from: d),
              let e = list.first(where: { $0.key.uppercased() == k })
        else { return .bad }

        guard let s = e.exp else { return .permanent }
        guard let date = ISO8601DateFormatter().date(from: s) else { return .bad }
        return date > Date() ? .timed(date) : .bad
    }

    func enter(_ raw: String) -> Bool {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch check(k) {
        case .permanent:
            exp = nil
            UserDefaults.standard.set(k, forKey: "vx.key")
            saved = k
            unlocked = true
            return true
        case .timed(let e):
            exp = e
            UserDefaults.standard.set(k, forKey: "vx.key")
            saved = k
            unlocked = true
            return true
        case .bad:
            return false
        }
    }

    func saveKey(_ raw: String) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !k.isEmpty else { return }
        UserDefaults.standard.set(k, forKey: "vx.key")
        saved = k
    }

    func eraseKey() {
        UserDefaults.standard.removeObject(forKey: "vx.key")
        saved = nil
        exp = nil
        unlocked = false
    }

    func lock() { unlocked = false }

    func left() -> String? {
        guard let e = exp else { return nil }
        let s = max(0, Int(e.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, x = s % 60
        return d > 0 ? String(format: "%dd %02d:%02d:%02d", d, h, m, x)
                     : String(format: "%02d:%02d:%02d", h, m, x)
    }

    func toggle(_ p: VXPatch) {
        if on.contains(p.id) { on.remove(p.id); play("off") } else { on.insert(p.id); play("on") }
    }

    func play(_ n: String) {
        guard !mute, let p = Bundle.main.path(forResource: n, ofType: "mp3", inDirectory: "veex") else { return }
        player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: p))
        player?.play()
    }
}

struct VXContact: View {
    var body: some View {
        HStack(spacing: 9) {
            link("CONTACTO", "https://t.me/levibrouh", VX.red)
            link("CANAL", "https://t.me/levibrouhs", VX.ink)
        }
    }

    private func link(_ t: String, _ u: String, _ c: Color) -> some View {
        Link(destination: URL(string: u)!) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill").font(.system(size: 10, weight: .bold))
                Text(t).font(.system(size: 9, weight: .black)).tracking(3)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(c)
        }
    }
}

struct VXDoor: View {
    @ObservedObject var s: VXStore
    @State private var key = ""
    @State private var bad = false
    @FocusState private var focus: Bool

    var body: some View {
        ZStack {
            VX.paper.ignoresSafeArea()
            VXSmoke().ignoresSafeArea()
            VXNoise().ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VXMark(size: 62)
                Text("EXTERNAL")
                    .font(.system(size: 9, weight: .black))
                    .tracking(9)
                    .foregroundStyle(VX.red)
                    .padding(.top, 12)
                Spacer()

                VStack(spacing: 10) {
                    Text("CLAVE DE ACCESO")
                        .font(.system(size: 8, weight: .black))
                        .tracking(4)
                        .foregroundStyle(VX.dim)

                    TextField("", text: $key)
                        .focused($focus)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(VX.ink)
                        .padding(.vertical, 13)
                        .background(VX.paper)
                        .overlay(Rectangle().stroke(bad ? VX.red : VX.ink.opacity(0.35), lineWidth: 1.2))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SOPORTADO: 17.0–18.7.10 · 26.0–26.7.2 · 27.0–27.2")
                            .font(.system(size: 7, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(VX.dim)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(vxIOSSupported() ? VX.green : VX.red)
                                .frame(width: 6, height: 6)
                            Text("\(vxIOSLabel()) · \(vxIOSSupported() ? "SOPORTADO" : "NO SOPORTADO")")
                                .font(.system(size: 8, weight: .black))
                                .tracking(1.6)
                                .foregroundStyle(vxIOSSupported() ? VX.green : VX.red)
                            Spacer()
                        }
                    }

                    if let saved = s.saved {
                        HStack(spacing: 6) {
                            Text("GUARDADA")
                                .font(.system(size: 8, weight: .black)).tracking(2)
                                .foregroundStyle(VX.dim)
                            Text(saved)
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundStyle(VX.ink.opacity(0.6))
                                .lineLimit(1)
                            Spacer()
                            if let l = s.left() {
                                Text(l)
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .foregroundStyle(VX.red)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            s.saveKey(key)
                        } label: {
                            Text("GUARDAR")
                                .font(.system(size: 9, weight: .black)).tracking(2.5)
                                .foregroundStyle(VX.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .overlay(Rectangle().stroke(VX.ink.opacity(0.4), lineWidth: 1.2))
                        }
                        Button {
                            s.eraseKey()
                            key = ""
                        } label: {
                            Text("BORRAR")
                                .font(.system(size: 9, weight: .black)).tracking(2.5)
                                .foregroundStyle(VX.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .overlay(Rectangle().stroke(VX.red, lineWidth: 1.2))
                        }
                    }

                    Button {
                        if !s.enter(key) {
                            bad = true
                            s.play("off")
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                            withAnimation(.default) { bad = false }
                        } else {
                            s.play("on")
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open.fill").font(.system(size: 11, weight: .bold))
                            Text("ENTRAR").font(.system(size: 12, weight: .black)).tracking(5)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(VX.red)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .vxSlab()
                .padding(.horizontal, 26)

                Spacer()

                VXContact()
                    .padding(.horizontal, 26)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            focus = true
            if let k = s.saved { key = k }
        }
    }
}

struct VXPanel: View {
    @ObservedObject var s: VXStore

    var body: some View {
        ZStack {
            VX.paper.ignoresSafeArea()
            VXNoise().ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabs
                if s.cat == .visual {
                    VXPreview(s: s)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(s.patches.filter { $0.cat == s.cat }) { p in
                                row(p)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                    }
                }
                footer
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                VXMark(size: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text("EXTERNAL").font(.system(size: 9, weight: .black)).tracking(4).foregroundStyle(VX.ink)
                    Text("VEEX").font(.system(size: 7, weight: .heavy)).tracking(3).foregroundStyle(VX.dim)
                }
                Spacer()
                Button { s.mute.toggle(); UserDefaults.standard.set(s.mute, forKey: "vx.mute") } label: {
                    Image(systemName: s.mute ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(s.mute ? VX.red : VX.dim)
                        .frame(width: 30, height: 30)
                        .overlay(Rectangle().stroke(VX.ink.opacity(0.18), lineWidth: 0.8))
                }
            }
            Rectangle().fill(VX.ink.opacity(0.12)).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(VXCat.allCases) { c in
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) { s.cat = c }
                    } label: {
                        Text(c.rawValue)
                            .font(.system(size: 8, weight: .black))
                            .tracking(2)
                            .foregroundStyle(s.cat == c ? .white : VX.ink.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(s.cat == c ? VX.ink : VX.paper)
                            .overlay(Rectangle().stroke(VX.ink.opacity(0.18), lineWidth: 0.8))
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func row(_ p: VXPatch) -> some View {
        let active = s.on.contains(p.id)
        return HStack(spacing: 11) {
            Rectangle().fill(active ? VX.green : VX.red).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.3)
                    .foregroundStyle(active ? VX.ink : VX.ink.opacity(0.6))
                if let n = s.note(p.id) {
                    Text(n)
                        .font(.system(size: 7, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(VX.red)
                }
            }
            Spacer()
            Button {
                s.toggle(p)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: active ? "checkmark" : "power").font(.system(size: 8, weight: .black))
                    Text(active ? "ON" : "OFF").font(.system(size: 9, weight: .black)).tracking(1.5)
                }
                .foregroundStyle(.white)
                .frame(width: 58, height: 28)
                .background(active ? VX.green : VX.red)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .vxSlab()
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Rectangle().fill(VX.ink.opacity(0.12)).frame(height: 1)
            HStack {
                Button {
                    s.lock()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
                        Text("BLOQUEAR").font(.system(size: 8, weight: .black)).tracking(3)
                    }
                    .foregroundStyle(VX.dim)
                }
                Spacer()
                if let l = s.left() {
                    Text(l)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(VX.red)
                } else {
                    Text("\(s.on.count) ACTIVOS")
                        .font(.system(size: 8, weight: .black)).tracking(2)
                        .foregroundStyle(VX.green)
                }
            }
            .padding(.top, 8)
            VXContact()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

struct VXRoot: View {
    @StateObject private var s = VXStore()
    var body: some View {
        ZStack {
            VX.paper.ignoresSafeArea()
            if s.unlocked { VXPanel(s: s) } else { VXDoor(s: s) }
        }
        .preferredColorScheme(.light)
    }
}

final class VXHost: UIHostingController<VXRoot> {
    init() { super.init(rootView: VXRoot()) }
    required init?(coder: NSCoder) { fatalError() }
}

@_cdecl("VXMakePanel")
public func VXMakePanel() -> UIViewController {
    let h = VXHost()
    h.view.backgroundColor = .white
    return h
}
