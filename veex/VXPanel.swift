import SwiftUI
import UIKit

// MARK: - Modelo

enum VXGroup {
    case aim, visual, util

    var label: String {
        switch self {
        case .aim: return "AIMBOTS"
        case .visual: return "VISUALES"
        case .util: return "UTILIDAD"
        }
    }
}

struct VXItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let file: String
    let group: VXGroup
    var autoOff: Bool = false
}

// MARK: - Estado

final class VXStore: ObservableObject {

    static let catalog: [VXItem] = [
        VXItem(id: "aim_drag",        title: "AIM DRAG",        detail: "arrastre pegado al enemigo", file: "aim_drag.3105",        group: .aim),
        VXItem(id: "aim_drag_antena", title: "AIM DRAG ANTENA", detail: "arrastre sobre la cabeza",   file: "aim_drag_antena.3105", group: .aim),
        VXItem(id: "aim_pecho",       title: "AIM PECHO",       detail: "arrastre al torso",          file: "aim_pecho.3105",       group: .aim),
        VXItem(id: "holo_personaje",  title: "HOLOGRAMA PERSONAJE", detail: "holograma en el modelo",  file: "holo_personaje.3105",  group: .visual),
        VXItem(id: "holo_armas",      title: "HOLOGRAMA ARMAS", detail: "holograma en el arma",       file: "holo_armas.3105",      group: .visual),
        VXItem(id: "balas_magicas",   title: "BALAS MÁGICAS",   detail: "trazadoras visibles",        file: "balas_magicas.3105",   group: .visual),
        VXItem(id: "reset_guest",     title: "RESET GUEST",     detail: "limpia el invitado y se apaga solo", file: "Reset Guest.3105", group: .util, autoOff: true)
    ]

    @Published var items: [VXItem] = VXStore.catalog
    @Published var on: Set<String> = []
    @Published var busy: String? = nil
    @Published var error: String? = nil
    @Published var note: String? = nil

    private let q = DispatchQueue(label: "veex.patch", qos: .userInitiated)

    static func syncNow() -> Set<String> {
        var live: Set<String> = []
        for item in catalog where VXApply.isOn(item.file) {
            live.insert(item.id)
        }
        return live
    }

    func refresh() {
        q.async {
            let live = VXStore.syncNow()
            DispatchQueue.main.async { self.on = live }
        }
    }

    func dismissError() {
        error = nil
        note = nil
    }

    func toggle(_ item: VXItem) {
        guard busy == nil else { return }
        let target = !on.contains(item.id)

        var exclusivos: [VXItem] = []
        if target && item.group == .aim {
            exclusivos = items.filter { $0.group == .aim && on.contains($0.id) && $0.id != item.id }
        }

        busy = item.id
        error = nil
        note = nil

        var optimista = on
        for old in exclusivos { optimista.remove(old.id) }
        if target { optimista.insert(item.id) } else { optimista.remove(item.id) }
        on = optimista

        q.async {
            do {
                for old in exclusivos { try VXApply.restore(old.file) }
                if target { try VXApply.apply(item.file) } else { try VXApply.restore(item.file) }

                var live = VXStore.syncNow()

                if target && item.autoOff {
                    Thread.sleep(forTimeInterval: 1.4)
                    try? VXApply.restore(item.file)
                    live = VXStore.syncNow()
                }

                let aviso: String
                if target {
                    aviso = item.autoOff ? "\(item.title) hecho." : "\(item.title) activo. Abre Free Fire."
                } else {
                    aviso = "\(item.title) restaurado."
                }

                DispatchQueue.main.async {
                    self.on = live
                    self.busy = nil
                    self.note = aviso
                }
            } catch let err {
                let msg = String(describing: err)
                let live = VXStore.syncNow()
                DispatchQueue.main.async {
                    self.on = live
                    self.busy = nil
                    self.error = msg
                }
            }
        }
    }
}

// MARK: - Abrir el juego

enum VXOpen {
    static let freeFire = "com.dts.freefireth"

    static func game() {
        if let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
            if let ws = cls.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() {
                _ = ws.perform(NSSelectorFromString("openApplicationWithBundleID:"), with: freeFire as NSString)
            }
        }
        if let url = URL(string: "freefire://") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

// MARK: - Panel

struct VXPanel: View {

    @StateObject private var store = VXStore()

    var body: some View {
        ZStack {
            VX.ink.ignoresSafeArea()
            VXSmoke().ignoresSafeArea()
            VXNoise().ignoresSafeArea()

            VStack(spacing: 0) {
                encabezado
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        VXPreview(s: store)
                            .frame(height: 208)
                            .vxCard(VX.ink)
                        seccion(.aim)
                        seccion(.visual)
                        seccion(.util)
                        VXEngineCard()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                }
                pie
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { store.refresh() }
    }

    private var encabezado: some View {
        HStack(spacing: 12) {
            VXMark(size: 20)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(store.on.count)")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundStyle(VX.red)
                Text("ACTIVOS")
                    .font(.system(size: 8, weight: .black))
                    .tracking(1.6)
                    .foregroundStyle(VX.dim)
            }
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(VX.paper)
                    .frame(width: 32, height: 32)
                    .background(VX.slab)
                    .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func seccion(_ group: VXGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(3)
                    .foregroundStyle(VX.dim)
                Rectangle().fill(VX.line).frame(height: 1)
            }
            ForEach(store.items.filter { $0.group == group }) { item in
                fila(item)
            }
        }
    }

    private func fila(_ item: VXItem) -> some View {
        let activo = store.on.contains(item.id)
        let cargando = store.busy == item.id
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(VX.paper)
                Text(item.detail)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VX.dim)
            }
            Spacer()
            if cargando {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(VX.red)
                    .frame(width: 46)
            } else {
                ZStack(alignment: activo ? .trailing : .leading) {
                    Rectangle()
                        .fill(activo ? VX.red : Color(white: 0.18))
                        .frame(width: 46, height: 24)
                    Rectangle()
                        .fill(VX.paper)
                        .frame(width: 20, height: 18)
                        .padding(.horizontal, 2)
                }
                .overlay(Rectangle().stroke(activo ? VX.red : VX.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VX.slab)
        .overlay(Rectangle().stroke(activo ? VX.red : VX.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { store.toggle(item) }
    }

    private var pie: some View {
        VStack(spacing: 7) {
            if let error = store.error {
                banner(error, VX.red)
            } else if let note = store.note {
                banner(note, VX.green)
            } else {
                Text("cierra free fire antes de mover un switch")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VX.dim)
            }

            Button {
                VXOpen.game()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .black))
                    Text("ABRIR FREE FIRE")
                        .font(.system(size: 12, weight: .black))
                        .tracking(2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(VX.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .background(VX.ink)
        .vxHair()
    }

    private func banner(_ texto: String, _ color: Color) -> some View {
        Text(texto)
            .font(.system(size: 9, weight: .black))
            .tracking(0.6)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(7)
            .background(VX.slab)
            .overlay(Rectangle().stroke(color, lineWidth: 1))
            .onTapGesture { store.dismissError() }
    }
}

// MARK: - Entrada para main.m

@_cdecl("VXMakePanel")
public func VXMakePanel() -> UIViewController {
    let host = UIHostingController(rootView: VXPanel())
    host.view.backgroundColor = .black
    host.view.isOpaque = true
    return host
}
