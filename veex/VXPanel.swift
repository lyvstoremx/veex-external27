import SwiftUI
import UIKit
import AVFoundation
import Darwin
import Security

let VXAdmin = "VEEX-LEVI-2004"
let VXAPI = "https://bot-veex.lyvstoremxweb.workers.dev"
let VXBuild = "1"
let VXGracia: TimeInterval = 43200

struct VXVerifyError: LocalizedError {
    var errorDescription: String? { "no quedó escrito" }
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

enum VXChain {
    static func get(_ c: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "veex",
            kSecAttrAccount as String: c,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ c: String, _ v: String) {
        del(c)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "veex",
            kSecAttrAccount as String: c,
            kSecValueData as String: Data(v.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func del(_ c: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "veex",
            kSecAttrAccount as String: c
        ]
        SecItemDelete(q as CFDictionary)
    }
}

func vxGameRunning() -> Bool {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size = 0
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return false }
    let cap = size / MemoryLayout<kinfo_proc>.stride + 16
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: cap)
    guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return false }
    let n = min(size / MemoryLayout<kinfo_proc>.stride, procs.count)
    for i in 0..<n {
        let name = withUnsafeBytes(of: procs[i].kp_proc.p_comm) { raw -> String in
            guard let base = raw.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: base)
        }
        if name.lowercased().contains("freefire") { return true }
    }
    return false
}

final class VXStore: ObservableObject {
    @Published var unlocked: Bool
    @Published var cat: VXCat = .visual
    @Published var on: Set<String> = []
    @Published var patches: [VXPatch] = []
    @Published var saved: String?
    @Published var exp: Date?
    @Published var fail: String?
    @Published var doorMsg: String?
    @Published var busy: String? = nil
    @Published var gameOpen = false
    @Published var now = Date()

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var watch: Timer?
    private var lastOK: Date?

    var iosOK: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let m = v.majorVersion, n = v.minorVersion, p = v.patchVersion
        if m == 17 { return n <= 7 }
        if m == 18 { return n < 7 || (n == 7 && p <= 10) }
        if m == 26 { return n < 7 || (n == 7 && p <= 2) }
        if m == 27 { return n < 2 || (n == 2 && p == 0) }
        return false
    }

    var iosLabel: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    var devID: String {
        if let d = VXChain.get("dev") { return d }
        let d = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        VXChain.set("dev", d)
        return d
    }

    init() {
        let d = UserDefaults.standard
        saved = d.string(forKey: "vx.key")
        unlocked = false
        if let t = d.object(forKey: "vx.last") as? Double {
            lastOK = Date(timeIntervalSince1970: t)
        }
        load()
        syncState()

        if let k = saved {
            if k == VXAdmin {
                unlocked = true
                exp = nil
            } else {
                verify()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
            if let e = self.exp, e <= Date(), self.unlocked {
                self.unlocked = false
                self.doorMsg = "clave vencida"
            }
        }
    }

    deinit {
        timer?.invalidate()
        watch?.invalidate()
    }

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
        if id == "guest" { return "no jugar con el encendido" }
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

    func startWatch() {
        checkGame()
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.checkGame()
        }
    }

    func stopWatch() {
        watch?.invalidate()
        watch = nil
    }

    func checkGame() {
        let open = vxGameRunning()
        if open != gameOpen { gameOpen = open }
    }

    private func motivo(_ raw: String) -> String {
        switch raw {
        case "clave": return "clave inválida"
        case "vencida": return "clave vencida"
        case "revocada": return "clave revocada"
        case "otro dispositivo": return "clave en otro dispositivo"
        case "suspendido": return "external suspendido"
        case "actualiza": return "actualiza la app"
        case "dispositivo tumbado": return "dispositivo bloqueado"
        case "datos": return "clave vacía"
        default: return "error"
        }
    }

    private func canje(_ key: String, done: @escaping (Bool, String?) -> Void) {
        guard let u = URL(string: VXAPI + "/canje") else { done(false, "url"); return }
        var r = URLRequest(url: u, timeoutInterval: 8)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "key": key, "device": devID, "build": VXBuild
        ])

        URLSession.shared.dataTask(with: r) { d, resp, err in
            DispatchQueue.main.async {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if err != nil || code == 0 {
                    done(false, "sin conexión")
                    return
                }
                let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                if code == 200, let ok = j["ok"] as? Bool, ok {
                    let e = (j["exp"] as? NSNumber)?.intValue ?? 0
                    if let t = j["token"] as? String { VXChain.set("tok", t) }
                    self.exp = e == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(e))
                    self.lastOK = Date()
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "vx.last")
                    UserDefaults.standard.set(key, forKey: "vx.key")
                    self.saved = key
                    self.doorMsg = nil
                    self.unlocked = true
                    done(true, nil)
                    return
                }
                done(false, self.motivo(j["err"] as? String ?? "error"))
            }
        }.resume()
    }

    func verify() {
        guard let tok = VXChain.get("tok"), let k = saved, k != VXAdmin, !k.isEmpty else { return }
        var comp = URLComponents(string: VXAPI + "/check")
        comp?.queryItems = [
            URLQueryItem(name: "device", value: devID),
            URLQueryItem(name: "key", value: k)
        ]
        guard let u = comp?.url else { return }
        var r = URLRequest(url: u, timeoutInterval: 6)
        r.setValue("Bearer " + tok, forHTTPHeaderField: "authorization")

        URLSession.shared.dataTask(with: r) { d, resp, err in
            DispatchQueue.main.async {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if err != nil || code == 0 || code >= 500 {
                    if let l = self.lastOK, Date().timeIntervalSince(l) < VXGracia {
                        self.unlocked = true
                    } else {
                        self.unlocked = false
                        self.doorMsg = "sin conexión"
                    }
                    return
                }
                if code == 200 {
                    let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                    let e = (j["exp"] as? NSNumber)?.intValue ?? 0
                    self.exp = e == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(e))
                    self.lastOK = Date()
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "vx.last")
                    self.doorMsg = nil
                    self.unlocked = true
                    return
                }
                let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                self.unlocked = false
                self.doorMsg = self.motivo(j["err"] as? String ?? "error")
            }
        }.resume()
    }

    func enter(_ raw: String, done: @escaping (Bool, String?) -> Void) {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !k.isEmpty else { done(false, "clave vacía"); return }

        if k == VXAdmin {
            UserDefaults.standard.set(k, forKey: "vx.key")
            saved = k
            exp = nil
            doorMsg = nil
            unlocked = true
            done(true, nil)
            return
        }

        canje(k) { ok, err in
            if !ok { self.doorMsg = err }
            done(ok, err)
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
        VXChain.del("tok")
        saved = nil
        exp = nil
        unlocked = false
        doorMsg = nil
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

        guard iosOK else {
            fail = iosLabel + " NO SOPORTADO"
            play("off")
            return
        }

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
                if target {
                    try VXApply.apply(p.file)
                    guard VXApply.isOn(p.file) else {
                        try? VXApply.restore(p.file)
                        throw VXVerifyError()
                    }
                } else {
                    try VXApply.restore(p.file)
                }

                DispatchQueue.main.async {
                    self.busy = nil
                    self.syncState()
                }
            } catch {
                let n = p.name
                let m = (error as? LocalizedError)?.errorDescription ?? "falló"
                DispatchQueue.main.async {
                    self.busy = nil
                    self.fail = "\(n) · \(m)"
                    self.syncState()
                    self.play("off")
                }
            }
        }
    }

    func restoreAll() {
        guard busy == nil else { return }
        let list = patches
        busy = "*"
        fail = nil

        DispatchQueue.global(qos: .userInitiated).async {
            var bad = 0
            for p in list where VXApply.isOn(p.file) {
                do { try VXApply.restore(p.file) } catch { bad += 1 }
            }
            DispatchQueue.main.async {
                self.busy = nil
                self.on = []
                self.syncState()
                if bad > 0 { self.fail = "fallaron \(bad)" }
                self.play(bad > 0 ? "off" : "on")
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
    @State private var busy = false
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
                                .fill(s.iosOK ? VX.green : VX.red)
                                .frame(width: 6, height: 6)
                            Text(s.iosLabel + " · " + (s.iosOK ? "SOPORTADO" : "NO SOPORTADO"))
                                .font(.system(size: 8, weight: .black))
                                .tracking(1.6)
                                .foregroundStyle(s.iosOK ? VX.green : VX.red)
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
                            } else if s.exp == nil {
                                Text("PERMANENTE")
                                    .font(.system(size: 9, weight: .black))
                                    .tracking(1.5)
                                    .foregroundStyle(VX.green)
                            }
                        }
                    }

                    if let m = s.doorMsg {
                        Text(m)
                            .font(.system(size: 8, weight: .black))
                            .tracking(1)
                            .foregroundStyle(VX.red)
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
                        guard !busy else { return }
                        busy = true
                        s.enter(key) { ok, _ in
                            busy = false
                            if !ok {
                                bad = true
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                                withAnimation(.default) { bad = false }
                            } else {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                        }
                    } label: {
                        HStack(spacing: 9) {
                            if busy {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: "lock.open.fill").font(.system(size: 12, weight: .bold))
                            }
                            Text("ENTRAR").font(.system(size: 13, weight: .black)).tracking(6)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VX.red)
                    }
                    .disabled(busy)
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
    @State private var diag = false
    @State private var confirmAll = false

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
                            if s.cat == .aimbot {
                                aviso("JUGAR CON EL MÉTODO 40%")
                            }
                            ForEach(s.patches.filter { $0.cat == s.cat }) { p in
                                row(p)
                            }
                            if s.cat == .extra {
                                Button { confirmAll = true } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "arrow.uturn.backward")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("RESTAURAR TODO")
                                            .font(.system(size: 9, weight: .black))
                                            .tracking(2)
                                    }
                                    .foregroundStyle(VX.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .overlay(Rectangle().stroke(VX.red, lineWidth: 1))
                                }
                                .disabled(s.busy != nil)
                                .padding(.top, 4)

                                Text("SOLO ÚSALO SI EL JUEGO QUEDÓ RARO")
                                    .font(.system(size: 7, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(VX.red)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                    }
                }
                footer
            }

            if diag {
                ZStack {
                    Color.black.opacity(0.96).ignoresSafeArea()
                    VStack(spacing: 10) {
                        HStack {
                            Text("DIAGNÓSTICO")
                                .font(.system(size: 10, weight: .black))
                                .tracking(4)
                                .foregroundStyle(VX.red)
                            Spacer()
                            Button {
                                withAnimation(.easeOut(duration: 0.12)) { diag = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(VX.dim)
                                    .frame(width: 32, height: 32)
                                    .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 16)

                        ScrollView {
                            VXEngineCard().padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            s.startWatch()
            s.verify()
        }
        .onDisappear { s.stopWatch() }
        .alert("RESTAURAR TODO", isPresented: $confirmAll) {
            Button("Restaurar", role: .destructive) { s.restoreAll() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Devuelve todos los parches y deja el juego limpio.")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                VXMark(size: 18)
                    .onLongPressGesture(minimumDuration: 3) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.easeOut(duration: 0.12)) { diag = true }
                    }
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

    private func aviso(_ t: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
            Text(t)
                .font(.system(size: 8, weight: .black))
                .tracking(1.4)
            Spacer()
        }
        .foregroundStyle(VX.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .vxCard(Color(white: 0.10))
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
                            .tint(active ? .black : VX.paper)
                            .scaleEffect(0.7)
                    } else {
                        Text(active ? "ON" : "OFF")
                            .font(.system(size: 9, weight: .black))
                            .tracking(2)
                            .foregroundStyle(active ? .black : VX.paper)
                    }
                }
                .frame(width: 56, height: 30)
                .background(active ? VX.green : VX.slab)
                .overlay(Rectangle().stroke(active ? .clear : VX.line, lineWidth: 1))
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

            if s.on.contains("guest") {
                HStack(spacing: 6) {
                    Circle().fill(VX.red).frame(width: 5, height: 5)
                    Text("RESET GUEST ACTIVO · RESTAURA TU CUENTA Y APÁGALO")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1)
                        .foregroundStyle(VX.red)
                    Spacer()
                }
            }

            if s.gameOpen && s.busy == nil {
                HStack(spacing: 6) {
                    Circle().fill(VX.red).frame(width: 5, height: 5)
                    Text("FREE FIRE ABIERTO · CIÉRRALO")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(VX.red)
                    Spacer()
                }
            }

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
                        .foregroundStyle(Int(s.exp?.timeIntervalSince(s.now) ?? 0) < 86400 ? VX.red : VX.dim)
                } else if s.exp == nil && s.saved != nil {
                    Text("PERMANENTE")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(VX.green)
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
