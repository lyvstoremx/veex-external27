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
    let file: String
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
    @Published var patches: [VXPatch] = []
    @Published var saved: String?
    @Published var exp: Date?
    @Published var fail: String?
    @Published var busy: String? = nil
    @Published var now = Date()

    private var player: AVAudioPlayer?
    private var timer: Timer?

    init() {
        let d = UserDefaults.standard
        saved = d.string(forKey: "vx.key")
        unlocked = false
        load()
        syncState()

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
            return VXPatch(id: vxID(n), name: pretty(n), file: f, cat: cat(of: n))
        }
    }

    private func vxID(_ n: String) -> String {
        let l = n.lowercased()
        if l.hasPrefix("holo_armas") { return "holoarm" }
        if l.hasPrefix("holo_personaje") { return "holoper" }
        if l.hasPrefix("reset") { return "guest" }
        if l.hasPrefix("aim_drag_antena") { return "antena" }
        if l == "aim_drag" { return "drag" }
        if l.hasPrefix("aim_pecho") { return "pecho" }
        if l.hasPrefix("balas") { return "balas" }
        return l.replacingOccurrences(of: " ", with: "")
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
        if id == "balas" || id == "holoarm" { return "bajo tu propio riesgo" }
        if id == "guest" { return "se apaga solo" }
        return nil
    }

    func syncState() {
        let list = patches
        DispatchQueue.global(qos: .userInitiated).async {
            var active = Set<String>()
            for p in list where VXApply.isOn(p.file) { active.insert(p.id) }
            DispatchQueue.main.async { self.on = active }
        }
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
        guard busy == nil else { return }
        let target = !on.contains(p.id)

        var others: [VXPatch] = []
        if target && p.cat == .aimbot {
            others = patches.filter { $0.cat == .aimbot && $0.id != p.id && on.contains($0.id) }
        }

        busy = p.id
        fail = nil
        if target { on.insert(p.id) } else { on.remove(p.id) }
        for o in others { on.remove(o.id) }
        play(target ? "on" : "off")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                for o in others { try VXApply.restore(o.file) }
                if target { try VXApply.apply(p.file) } else { try VXApply.restore(p.file) }

                if target && p.id == "guest" {
                    Thread.sleep(forTimeInterval: 1.4)
                    try? VXApply.restore(p.file)
                }

                DispatchQueue.main.async {
                    self.busy = nil
                    self.syncState()
                }
            } catch {
                let n = p.name
                DispatchQueue.main.async {
                    self.busy = nil
                    self.fail = "falló: " + n
                    self.syncState()
                    self.play("off")
                }
            }
        }
    }

    func openGame() {
        for s in ["freefire://", "freefiremax://"] {
            guard let u = URL(string: s) else { continue }
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
            return
        }
    }

    func play(_ n: String) {
        guard let p = Bundle.main.path(forResource: n, ofType: "mp3", inDirectory: "veex") else { return }
        player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: p))
        player?.play()
    }
}

struct VXContact: View {
    var body: some View {
        HStack(spacing: 8) {
            link("CONTACTO", "https://t.me/levibrouh", VX.red)
            link("CANAL", "https://t.me/levibrouhs", VX.slab)
        }
    }

    private func link(_ t: String, _ u: String, _ c: Color) -> some View {
        Link(destination: URL(string: u)!) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill").font(.system(size: 10, weight: .bold))
                Text(t).font(.system(size: 9, weight: .black)).tracking(3)
            }
            .foregroundStyle(c == VX.slab ? VX.paper : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(c)
            .overlay(Rectangle().stroke(c == VX.slab ? VX.line : .clear, lineWidth: 1))
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
            VX.ink.ignoresSafeArea()
            VXSmoke().ignoresSafeArea()
            VXNoise().ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VXMark(size: 66)
                Text("EXTERNAL")
                    .font(.system(size: 10, weight: .black))
                    .tracking(11)
                    .foregroundStyle(VX.red)
                    .padding(.top, 16)
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text("CLAVE DE ACCESO")
                        .font(.system(size: 8, weight: .black))
                        .tracking(4)
                        .foregroundStyle(VX.dim)

                    TextField("", text: $key)
                        .focused($focus)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(VX.paper)
                        .padding(.vertical, 15)
                        .background(Color.black.opacity(0.5))
                        .overlay(Rectangle().stroke(bad ? VX.red : VX.line, lineWidth: 1.2))

                    VStack(alignment: .leading, spacing: 4) {
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
                        }
                    }

                    if let saved = s.saved {
                        HStack(spacing: 6) {
                            Text(saved)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(VX.dim)
                                .lineLimit(1)
                            Spacer()
                            if let l = s.left() {
                                Text(l)
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
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
                                .foregroundStyle(VX.paper)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                        }
                        Button {
                            s.eraseKey()
                            key = ""
                        } label: {
                            Text("BORRAR")
                                .font(.system(size: 9, weight: .black)).tracking(2.5)
                                .foregroundStyle(VX.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .overlay(Rectangle().stroke(VX.red, lineWidth: 1))
                        }
                    }

                    Button {
                        if !s.enter(key) {
                            bad = true
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                            withAnimation(.default) { bad = false }
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "lock.open.fill").font(.system(size: 12, weight: .bold))
                            Text("ENTRAR").font(.system(size: 13, weight: .black)).tracking(6)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VX.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .vxCard()

                Spacer()

                VXContact()

                Text("BY LEVI")
                    .font(.system(size: 7, weight: .black))
                    .tracking(5)
                    .foregroundStyle(VX.dim)
                    .padding(.top, 14)
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, 26)
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
            VX.ink.ignoresSafeArea()
            VXNoise().ignoresSafeArea()

            VStack(spacing: 0) {
                header
                tabs
                if s.cat == .visual {
                    VXPreview(s: s)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
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
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                VXMark(size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXTERNAL").font(.system(size: 10, weight: .black)).tracking(5).foregroundStyle(VX.paper)
                    Text("BY LEVI").font(.system(size: 7, weight: .heavy)).tracking(3).foregroundStyle(VX.red)
                }
                Spacer()
                Button { s.lock() } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VX.dim)
                        .frame(width: 32, height: 32)
                        .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                }
            }
            Rectangle().fill(VX.line).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(VXCat.allCases) { c in
                    Button {
                        withAnimation(.easeOut(duration: 0.1)) { s.cat = c }
                    } label: {
                        Text(c.rawValue)
                            .font(.system(size: 8, weight: .black))
                            .tracking(2)
                            .foregroundStyle(s.cat == c ? .white : VX.dim)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(s.cat == c ? VX.red : VX.slab)
                            .overlay(Rectangle().stroke(s.cat == c ? .clear : VX.line, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func row(_ p: VXPatch) -> some View {
        let active = s.on.contains(p.id)
        let working = s.busy == p.id
        return HStack(spacing: 12) {
            Rectangle().fill(active ? VX.green : VX.line).frame(width: 2, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name)
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(active ? VX.paper : VX.dim)
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
                ZStack {
                    if working {
                        ProgressView()
                            .tint(active ? .black : .white)
                            .scaleEffect(0.7)
                    } else {
                        Text(active ? "ON" : "OFF")
                            .font(.system(size: 9, weight: .black))
                            .tracking(2)
                            .foregroundStyle(active ? .black : .white)
                    }
                }
                .frame(width: 56, height: 30)
                .background(active ? VX.green : VX.red)
            }
            .disabled(s.busy != nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .vxCard(Color(white: 0.10))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle().fill(VX.line).frame(height: 1)

            if let f = s.fail {
                Text(f)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(VX.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button { s.openGame() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 11, weight: .bold))
                    Text("ABRIR FREE FIRE").font(.system(size: 11, weight: .black)).tracking(2)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(VX.green)
            }

            HStack {
                Text("\(s.on.count) ACTIVOS")
                    .font(.system(size: 8, weight: .black)).tracking(2)
                    .foregroundStyle(VX.green)
                Spacer()
                if let l = s.left() {
                    Text(l)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(VX.red)
                }
            }
            VXContact()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

struct VXRoot: View {
    @StateObject private var s = VXStore()
    var body: some View {
        ZStack {
            VX.ink.ignoresSafeArea()
            if s.unlocked { VXPanel(s: s) } else { VXDoor(s: s) }
        }
        .preferredColorScheme(.dark)
    }
}

final class VXHost: UIHostingController<VXRoot> {
    init() { super.init(rootView: VXRoot()) }
    required init?(coder: NSCoder) { fatalError() }
}

@_cdecl("VXMakePanel")
public func VXMakePanel() -> UIViewController {
    let h = VXHost()
    h.view.backgroundColor = .black
    return h
}
