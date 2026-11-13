import SwiftUI
import UIKit
import AVFoundation

let VXAdmin = "VEEX-LEVI-2004"

enum VXCat: String, CaseIterable, Identifiable {
    case personaje = "PERSONAJE"
    case armas = "ARMAS"
    case aimbot = "AIMBOT"
    case extra = "EXTRA"
    case visual = "VISUAL"
    var id: String { rawValue }
}

struct VXPatch: Identifiable {
    let id: String
    let name: String
    let cat: VXCat
}

final class VXStore: ObservableObject {
    @Published var unlocked: Bool
    @Published var cat: VXCat = .personaje
    @Published var on: Set<String> = []
    @Published var mute: Bool
    @Published var patches: [VXPatch] = []

    private var player: AVAudioPlayer?

    init() {
        let d = UserDefaults.standard
        unlocked = d.bool(forKey: "vx.unlocked")
        mute = d.bool(forKey: "vx.mute")
        load()
    }

    private func load() {
        let dir = Bundle.main.bundlePath + "/veex"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        patches = files.filter { $0.hasSuffix(".3105") }.sorted().map { f in
            let n = (f as NSString).deletingPathExtension
            return VXPatch(id: n, name: n.replacingOccurrences(of: "_", with: " ").uppercased(), cat: cat(of: n))
        }
    }

    private func cat(of n: String) -> VXCat {
        let l = n.lowercased()
        if l.hasPrefix("holo_personaje") { return .personaje }
        if l.hasPrefix("holo_armas") { return .armas }
        if l.hasPrefix("aim_") || l.hasPrefix("balas") { return .aimbot }
        return .extra
    }

    func validate(_ key: String) -> Bool {
        guard key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == VXAdmin else { return false }
        UserDefaults.standard.set(true, forKey: "vx.unlocked")
        unlocked = true
        return true
    }

    func lock() {
        UserDefaults.standard.set(false, forKey: "vx.unlocked")
        unlocked = false
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

struct VXDoor: View {
    @ObservedObject var s: VXStore
    @State private var key = ""
    @State private var bad = false
    @FocusState private var focus: Bool

    var body: some View {
        GeometryReader { g in
            ZStack {
                VX.ink.ignoresSafeArea()
                VXSmoke().ignoresSafeArea()
                VXNoise().ignoresSafeArea()
                VXVignette().ignoresSafeArea()

                VStack(spacing: 0) {
                    VXMark(size: 44)
                        .padding(.top, 24)
                    Text("PRUEBA VISUAL")
                        .font(.system(size: 8, weight: .black))
                        .tracking(6)
                        .foregroundStyle(VX.red)
                        .padding(.top, 10)

                    VXPreview(s: s, header: false)
                        .frame(height: g.size.height * 0.44)

                    plate
                    Spacer(minLength: 10)
                }
            }
        }
        .onAppear { focus = true }
    }

    private var plate: some View {
        VStack(spacing: 12) {
            Text("CLAVE")
                .font(.system(size: 9, weight: .black))
                .tracking(5)
                .foregroundStyle(VX.dim)

            TextField("", text: $key)
                .focused($focus)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(VX.paper)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.75))
                .overlay(Rectangle().stroke(bad ? VX.red : Color(white: 0.26), lineWidth: 1))

            Button {
                if !s.validate(key) {
                    bad = true
                    s.play("off")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    withAnimation(.default) { bad = false }
                } else {
                    s.play("on")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                Text("ENTRAR")
                    .font(.system(size: 12, weight: .black))
                    .tracking(5)
                    .foregroundStyle(VX.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(VX.red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .vxSlab()
        .padding(.horizontal, 26)
    }
}

struct VXPanel: View {
    @ObservedObject var s: VXStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VX.ink.ignoresSafeArea()
            VXNoise().ignoresSafeArea()
            VXVignette().ignoresSafeArea()

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
        HStack(alignment: .center) {
            VXMark(size: 18)
            Text("EXTERNAL")
                .font(.system(size: 9, weight: .black))
                .tracking(4)
                .foregroundStyle(VX.dim)
            Spacer()
            Button { s.mute.toggle(); UserDefaults.standard.set(s.mute, forKey: "vx.mute") } label: {
                Image(systemName: s.mute ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VX.dim)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VX.paper)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
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
                            .foregroundStyle(s.cat == c ? VX.paper : VX.dim)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(s.cat == c ? VX.red : Color(white: 0.11))
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 10)
    }

    private func row(_ p: VXPatch) -> some View {
        HStack(spacing: 11) {
            Rectangle()
                .fill(s.on.contains(p.id) ? VX.red : Color(white: 0.2))
                .frame(width: 2, height: 20)
            Text(p.name)
                .font(.system(size: 11, weight: .black))
                .tracking(1.4)
                .foregroundStyle(s.on.contains(p.id) ? VX.paper : Color(white: 0.55))
            Spacer()
            Toggle("", isOn: Binding(get: { s.on.contains(p.id) }, set: { _ in s.toggle(p) }))
                .labelsHidden()
                .scaleEffect(0.82)
                .tint(VX.red)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .vxSlab()
    }

    private var footer: some View {
        HStack {
            Button("BLOQUEAR") { s.lock() }
                .font(.system(size: 8, weight: .black)).tracking(3)
                .foregroundStyle(VX.dim)
            Spacer()
            Text("\(s.on.count) ACTIVOS")
                .font(.system(size: 8, weight: .black)).tracking(2)
                .foregroundStyle(VX.red)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
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
