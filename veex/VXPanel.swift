import SwiftUI
import UIKit

// MARK: - Modelo

enum VXGroup: String {
    case aim = "AIMBOTS"
    case visual = "VISUALES"
    case util = "UTILIDAD"
}

struct VXItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let group: VXGroup
    var file: String { id + ".3105" }
}

// MARK: - Estado

final class VXStore: ObservableObject {

    static let catalog: [VXItem] = [
        VXItem(id: "aim_drag",        title: "AIM DRAG",        detail: "Arrastre pegado al enemigo",   group: .aim),
        VXItem(id: "aim_drag_antena", title: "AIM DRAG ANTENA", detail: "Arrastre sobre la cabeza",     group: .aim),
        VXItem(id: "aim_pecho",       title: "AIM PECHO",       detail: "Arrastre al torso",            group: .aim),
        VXItem(id: "holo_personaje",  title: "HOLOGRAMA PERSONAJE", detail: "Holograma en el modelo",   group: .visual),
        VXItem(id: "holo_armas",      title: "HOLOGRAMA ARMAS", detail: "Holograma en el arma",         group: .visual),
        VXItem(id: "balas_magicas",   title: "BALAS MÁGICAS",   detail: "Trazadoras visibles",          group: .visual),
        VXItem(id: "reset_guest",     title: "RESET GUEST",     detail: "Limpia el invitado",           group: .util)
    ]

    @Published var items: [VXItem] = VXStore.catalog
    @Published var on: Set<String> = []
    @Published var busy: String? = nil
    @Published var error: String? = nil
    @Published var note: String? = nil

    private let q = DispatchQueue(label: "veex.patch", qos: .userInitiated)

    static func syncNow() -> Set<String> {
        var live: Set<String> = []
        for item in catalog {
            if (try? VXApply.isOn(item.file)) ?? false { live.insert(item.id) }
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
                let live = VXStore.syncNow()
                DispatchQueue.main.async {
                    self.on = live
                    self.busy = nil
                    self.note = target ? "\(item.title) activo. Abre Free Fire." : "\(item.title) restaurado."
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

    private let fondo = Color(red: 0.05, green: 0.06, blue: 0.09)
    private let carta = Color(red: 0.10, green: 0.11, blue: 0.15)
    private let acento = Color(red: 0.35, green: 0.85, blue: 0.65)

    var body: some View {
        ZStack {
            fondo.ignoresSafeArea()
            VStack(spacing: 0) {
                encabezado
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        seccion(.aim)
                        seccion(.visual)
                        seccion(.util)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
                pie
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { store.refresh() }
    }

    private var encabezado: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("VEEX")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("3105 · iOS 17 – 27.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(store.on.count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(acento)
                Text("ACTIVOS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
            }
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray)
                    .padding(8)
                    .background(carta)
                    .clipShape(Circle())
            }
            .padding(.leading, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func seccion(_ group: VXGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.rawValue)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.gray)
                .padding(.leading, 4)
            ForEach(store.items.filter { $0.group == group }) { item in
                fila(item)
            }
        }
    }

    private func fila(_ item: VXItem) -> some View {
        let activo = store.on.contains(item.id)
        let cargando = store.busy == item.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            Spacer()
            if cargando {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                ZStack(alignment: activo ? .trailing : .leading) {
                    Capsule()
                        .fill(activo ? acento : Color(white: 0.25))
                        .frame(width: 44, height: 25)
                    Circle()
                        .fill(.white)
                        .frame(width: 19, height: 19)
                        .padding(.horizontal, 3)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(carta)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(activo ? acento.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { store.toggle(item) }
    }

    private var pie: some View {
        VStack(spacing: 8) {
            if let error = store.error {
                Text(error)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 1, green: 0.42, blue: 0.42))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(red: 0.16, green: 0.07, blue: 0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .onTapGesture { store.dismissError() }
            } else if let note = store.note {
                Text(note)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(acento)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(red: 0.06, green: 0.14, blue: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .onTapGesture { store.dismissError() }
            } else {
                Text("Cierra Free Fire antes de mover un switch")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Button {
                VXOpen.game()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("ABRIR FREE FIRE")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundColor(Color(red: 0.03, green: 0.09, blue: 0.07))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(acento)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .background(fondo)
    }
}
