import SwiftUI
import UIKit
import AVFoundation

let VXMaster = ["VEEX-LEVI-2004", "VEEX-LEVI-FF26"]

enum VXCat: String, CaseIterable, Identifiable {
    case personaje = "Personaje"
    case armas = "Armas"
    case aimbot = "Aimbot"
    case extra = "Extra"
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
            return VXPatch(id: n, name: n.replacingOccurrences(of: "_", with: " ").capitalized, cat: cat(of: n))
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
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var valid = VXMaster.contains(k)
        if !valid, let p = Bundle.main.path(forResource: "keys", ofType: "json", inDirectory: "veex"),
           let data = FileManager.default.contents(atPath: p),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            valid = list.map { $0.uppercased() }.contains(k)
        }
        if valid {
            UserDefaults.standard.set(true, forKey: "vx.unlocked")
            unlocked = true
        }
        return valid
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
        ZStack {
            metal
            VStack(spacing: 0) {
                Spacer()
                Text("VEEX")
                    .font(.system(size: 46, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2)
                Text("EXTERNAL")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(8)
                    .foregroundStyle(Color(red: 0.85, green: 0.1, blue: 0.12))
                    .padding(.top, 6)
                Spacer()
                plate
                Spacer()
            }
        }
        .onAppear { focus = true }
    }

    private var metal: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.24), Color(white: 0.09), Color(white: 0.19)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 3) {
                ForEach(0..<90, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(0.035)).frame(height: 1)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    private var plate: some View {
        VStack(spacing: 14) {
            Text("CLAVE")
                .font(.system(size: 10, weight: .heavy))
                .tracking(4)
                .foregroundStyle(Color(white: 0.55))

            TextField("", text: $key)
                .focused($focus)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.vertical, 13)
                .background(Color.black.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(bad ? Color.red : Color(white: 0.3), lineWidth: 1))
                .cornerRadius(7)
                .padding(.horizontal, 26)

            Button {
                if !s.validate(key) {
                    bad = true
                    s.play("off")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    withAnimation(.default) { bad = false }
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                Text("ENTRAR")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.72, green: 0.07, blue: 0.09))
                    .cornerRadius(7)
                    .padding(.horizontal, 26)
            }
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.11)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.7), radius: 12, y: 6)
        )
        .padding(.horizontal, 34)
    }
}

struct VXPanel: View {
    @ObservedObject var s: VXStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Picker("", selection: $s.cat) {
                    ForEach(VXCat.allCases) { c in Text(c.rawValue).tag(c) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(s.patches.filter { $0.cat == s.cat }) { p in
                            row(p)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                footer
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VEEX").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                Text("EXTERNAL").font(.system(size: 9, weight: .bold)).tracking(5)
                    .foregroundStyle(Color(red: 0.85, green: 0.1, blue: 0.12))
            }
            Spacer()
            Button { s.mute.toggle(); UserDefaults.standard.set(s.mute, forKey: "vx.mute") } label: {
                Image(systemName: s.mute ? "speaker.slash" : "speaker.wave.2")
                    .foregroundStyle(.white)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").foregroundStyle(.white)
            }
        }
        .padding(16)
    }

    private func row(_ p: VXPatch) -> some View {
        HStack {
            Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: Binding(get: { s.on.contains(p.id) }, set: { _ in s.toggle(p) }))
                .labelsHidden()
                .tint(Color(red: 0.72, green: 0.07, blue: 0.09))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(white: 0.1))
        .cornerRadius(9)
    }

    private var footer: some View {
        HStack {
            Button("BLOQUEAR") { s.lock() }
                .font(.system(size: 11, weight: .heavy)).tracking(2)
                .foregroundStyle(Color(white: 0.5))
            Spacer()
            Text("\(s.on.count) activos")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(white: 0.4))
        }
        .padding(16)
    }
}

struct VXRoot: View {
    @StateObject private var s = VXStore()
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
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
