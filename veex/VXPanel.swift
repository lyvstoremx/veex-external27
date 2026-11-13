import SwiftUI
import UIKit
import AVFoundation

let VXAdmin = "VEEX-LEVI-2004"

enum VXCat: String, CaseIterable, Identifiable {
    case visual = "VISUAL"
    case personaje = "PERSONAJE"
    case armas = "ARMAS"
    case aimbot = "AIMBOT"
    case extra = "EXTRA"
    var id: String { rawValue }
}

struct VXPatch: Identifiable {
    let id: String
    let name: String
    let cat: VXCat
}

final class VXStore: ObservableObject {
    @Published var unlocked: Bool
    @Published var cat: VXCat = .visual
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

struct VXContact: View {
    var body: some View {
        HStack(spacing: 10) {
            link("CONTACTO", "https://t.me/levibrouh", VX.red)
            link("CANAL", "https://t.me/levibrouhs", VX.ink)
        }
    }

    private func link(_ t: String, _ u: String, _ c: Color) -> some View {
        Link(destination: URL(string: u)!) {
            Text(t)
                .font(.system(size: 9, weight: .black))
                .tracking(3)
                .foregroundStyle(c == VX.ink ? .white : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
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
                VXMark(size: 58)
                Text("EXTERNAL")
                    .font(.system(size: 9, weight: .black))
                    .tracking(8)
                    .foregroundStyle(VX.red)
                    .padding(.top, 12)
                Spacer()

                VStack(spacing: 11) {
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
                        .foregroundStyle(VX.ink)
                        .padding(.vertical, 12)
                        .background(VX.paper)
                        .overlay(Rectangle().stroke(bad ? VX.red : VX.ink.opacity(0.35), lineWidth: 1.2))

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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
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
                    .padding(.bottom, 26)
            }
        }
        .onAppear { focus = true }
    }
}

struct VXPanel: View {
    @ObservedObject var s: VXStore
    @Environment(\.dismiss) private var dismiss

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
        HStack(spacing: 8) {
            VXMark(size: 17)
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
                    .foregroundStyle(VX.ink)
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
                            .foregroundStyle(s.cat == c ? .white : VX.ink.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(s.cat == c ? VX.ink : VX.paper)
                            .overlay(Rectangle().stroke(VX.ink.opacity(0.18), lineWidth: 0.8))
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 10)
    }

    private func row(_ p: VXPatch) -> some View {
        let active = s.on.contains(p.id)
        return HStack(spacing: 11) {
            Rectangle()
                .fill(active ? VX.green : VX.red)
                .frame(width: 3, height: 22)
            Text(p.name)
                .font(.system(size: 11, weight: .black))
                .tracking(1.4)
                .foregroundStyle(active ? VX.ink : VX.ink.opacity(0.6))
            Spacer()
            Button {
                s.toggle(p)
            } label: {
                Text(active ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 28)
                    .background(active ? VX.green : VX.red)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .vxSlab()
    }

    private var footer: some View {
        VStack(spacing: 9) {
            HStack {
                Button("BLOQUEAR") { s.lock() }
                    .font(.system(size: 8, weight: .black)).tracking(3)
                    .foregroundStyle(VX.dim)
                Spacer()
                Text("\(s.on.count) ACTIVOS")
                    .font(.system(size: 8, weight: .black)).tracking(2)
                    .foregroundStyle(VX.green)
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
