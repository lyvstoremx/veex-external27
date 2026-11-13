import SwiftUI

struct VXPreview: View {
    @ObservedObject var s: VXStore
    @State private var angle: Double = 0
    @State private var base: Double = 0
    @State private var pulse = false

    private struct Callout {
        let id: String?
        let label: String
        let x: CGFloat
        let y: CGFloat
        let back: Bool
    }

    private let marks: [Callout] = [
        .init(id: nil, label: "HEAD", x: 0.50, y: 0.12, back: false),
        .init(id: nil, label: "NECK", x: 0.50, y: 0.23, back: false),
        .init(id: "aim_pecho", label: "PECHO", x: 0.50, y: 0.33, back: false),
        .init(id: "aim_drag", label: "DRAG", x: 0.19, y: 0.60, back: false),
        .init(id: "balas_magicas", label: "BALAS MÁGICAS", x: 0.81, y: 0.58, back: false),
        .init(id: nil, label: "ESPALDA", x: 0.50, y: 0.40, back: true)
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("VISUALIZACIÓN")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(Color(white: 0.45))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { angle = 0; base = 0 }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            GeometryReader { g in
                let w = g.size.width
                let h = g.size.height
                ZStack {
                    radar(w: w)
                    figure(w: w, h: h)
                    labels(w: w, h: h)
                    Text("arrastra para girar")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: 0.35))
                        .position(x: w * 0.5, y: h * 0.97)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            angle = max(-180, min(180, base + Double(v.translation.width) * 0.7))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                                if abs(angle) < 30 { angle = 0 }
                                else if angle > 120 { angle = 180 }
                                else if angle < -120 { angle = -180 }
                                base = angle
                            }
                        }
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func radar(w: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color(red: 0.72, green: 0.07, blue: 0.09).opacity(0.3), lineWidth: 1)
                    .frame(width: w * (0.45 + CGFloat(i) * 0.2))
            }
        }
        .opacity(0.8)
    }

    private func figure(w: CGFloat, h: CGFloat) -> some View {
        let facing = abs(angle) < 90
        return ZStack {
            if let img = load(facing ? "vx_front" : "vx_back") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: facing ? 1 : -1, y: 1)
                    .scaleEffect(pulse ? 1.01 : 1.0)
            } else {
                Text("faltan las imágenes")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
        .frame(height: h * 0.9)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
    }

    private func load(_ n: String) -> UIImage? {
        guard let p = Bundle.main.path(forResource: n, ofType: "png", inDirectory: "veex") else { return nil }
        return UIImage(contentsOfFile: p)
    }

    private func labels(w: CGFloat, h: CGFloat) -> some View {
        let showFront = abs(angle) < 55
        let showBack = abs(angle) > 125
        return ForEach(marks.indices, id: \.self) { i in
            let m = marks[i]
            if m.back ? showBack : showFront {
                mark(m, w: w, h: h)
            }
        }
    }

    private func mark(_ m: Callout, w: CGFloat, h: CGFloat) -> some View {
        let active = m.id.map { s.on.contains($0) } ?? false
        return Text(m.label)
            .font(.system(size: 9, weight: .heavy))
            .tracking(1)
            .foregroundStyle(active ? .white : Color(white: 0.68))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(active ? Color(red: 0.72, green: 0.07, blue: 0.09) : Color(white: 0.14))
            .overlay(
                Capsule().stroke(active ? Color.white.opacity(0.5)
                                        : Color(red: 0.85, green: 0.1, blue: 0.12).opacity(0.45), lineWidth: 1)
            )
            .clipShape(Capsule())
            .position(x: w * m.x, y: h * m.y)
            .onTapGesture {
                guard let id = m.id, let p = s.patches.first(where: { $0.id == id }) else { return }
                s.toggle(p)
            }
    }
}
