import SwiftUI

struct VXPreview: View {
    @ObservedObject var s: VXStore
    @State private var angle: Double = 0
    @State private var base: Double = 0
    @State private var sway = false

    private struct Mark {
        let label: String
        let lx: CGFloat
        let ly: CGFloat
        let px: CGFloat
        let py: CGFloat
        let back: Bool
    }

    private let marks: [Mark] = [
        .init(label: "PECHO", lx: 0.14, ly: 0.38, px: 0.44, py: 0.33, back: false),
        .init(label: "DRAG", lx: 0.17, ly: 0.20, px: 0.44, py: 0.24, back: false),
        .init(label: "BALAS MÁGICAS", lx: 0.82, ly: 0.58, px: 0.60, py: 0.52, back: false),
        .init(label: "ESPALDA", lx: 0.50, ly: 0.08, px: 0.50, py: 0.30, back: true)
    ]

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("VISUALIZACIÓN")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(4)
                    .foregroundStyle(Color(white: 0.45))
                Spacer()
                Text("solo referencia")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(white: 0.3))
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
                    arcs(w: w)
                    connectors(w: w, h: h)
                    figure(w: w, h: h)
                    labels(w: w, h: h)
                    Text("arrastra para girar")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: 0.32))
                        .position(x: w * 0.5, y: h * 0.975)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            angle = max(-180, min(180, base + Double(v.translation.width) * 0.7))
                        }
                        .onEnded { _ in
                            let target: Double = abs(angle) >= 90 ? (angle > 0 ? 180 : -180) : 0
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { angle = target }
                            base = target
                        }
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { sway = true }
        }
    }

    private func arcs(w: CGFloat) -> some View {
        ZStack {
            Circle()
                .trim(from: 0.55, to: 0.95)
                .stroke(Color(red: 0.85, green: 0.1, blue: 0.12).opacity(0.55), lineWidth: 1.5)
                .frame(width: w * 0.86, height: w * 0.86)
            Circle()
                .trim(from: 0.05, to: 0.45)
                .stroke(Color(white: 0.35), lineWidth: 1)
                .frame(width: w * 0.86, height: w * 0.86)
        }
    }

    private func connectors(w: CGFloat, h: CGFloat) -> some View {
        let showFront = abs(angle) < 55
        let showBack = abs(angle) > 125
        return Canvas { ctx, _ in
            for m in marks {
                if m.back ? !showBack : !showFront { continue }
                var p = Path()
                p.move(to: CGPoint(x: w * m.lx, y: h * m.ly))
                p.addLine(to: CGPoint(x: w * m.px, y: h * m.py))
                ctx.stroke(p,
                           with: .color(.white.opacity(0.22)),
                           style: StrokeStyle(lineWidth: 0.8, dash: [2.5, 3]))
                ctx.fill(Path(ellipseIn: CGRect(x: w * m.px - 2, y: h * m.py - 2, width: 4, height: 4)),
                         with: .color(.white.opacity(0.6)))
            }
        }
    }

    private func figure(w: CGFloat, h: CGFloat) -> some View {
        let facing = abs(angle) < 90
        return Group {
            if let img = load(facing ? "vx_front" : "vx_back") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: facing ? 1 : -1, y: 1)
            } else {
                Text("faltan las imágenes")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
        .frame(height: h * 0.92)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
        .offset(y: sway ? -2 : 2)
        .shadow(color: .black.opacity(0.7), radius: 12, y: 6)
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
                Text(m.label)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color(white: 0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .overlay(Rectangle().stroke(Color(white: 0.3), lineWidth: 0.8))
                    .position(x: w * m.lx, y: h * m.ly)
            }
        }
    }
}
