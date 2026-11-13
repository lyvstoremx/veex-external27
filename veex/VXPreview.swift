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
    }

    private let marks: [Mark] = [
        .init(label: "DRAG", lx: 0.16, ly: 0.20, px: 0.44, py: 0.22),
        .init(label: "PECHO", lx: 0.15, ly: 0.36, px: 0.44, py: 0.34),
        .init(label: "BALAS MÁGICAS", lx: 0.78, ly: 0.62, px: 0.60, py: 0.55)
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
                    figure(w: w, h: h)
                    overlay(w: w, h: h)
                    Text("arrastra para girar")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: 0.32))
                        .position(x: w * 0.5, y: h * 0.99)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            angle = max(-180, min(180, base + Double(v.translation.width) * 0.6))
                        }
                        .onEnded { _ in
                            let snapped = max(-180, min(180, (angle / 90).rounded() * 90))
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { angle = snapped }
                            base = snapped
                        }
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { sway = true }
        }
    }

    private func name() -> String {
        if abs(angle) >= 135 { return "vx_back" }
        if angle >= 45 { return "vx_right" }
        if angle <= -45 { return "vx_left" }
        return "vx_front"
    }

    private func figure(w: CGFloat, h: CGFloat) -> some View {
        Group {
            if let img = load(name()) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: abs(angle) >= 135 ? -1 : 1, y: 1)
            } else {
                Text("faltan las imágenes")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
        .frame(height: h * 0.94)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.3)
        .offset(y: sway ? -2 : 2)
        .shadow(color: .black.opacity(0.7), radius: 12, y: 6)
    }

    private func load(_ n: String) -> UIImage? {
        guard let p = Bundle.main.path(forResource: n, ofType: "png", inDirectory: "veex") else { return nil }
        return UIImage(contentsOfFile: p)
    }

    private func overlay(w: CGFloat, h: CGFloat) -> some View {
        let vis = max(0, 1 - abs(angle) / 55)
        return Canvas { ctx, _ in
            for m in marks {
                var line = Path()
                line.move(to: CGPoint(x: w * m.lx, y: h * m.ly))
                line.addLine(to: CGPoint(x: w * m.px, y: h * m.py))
                ctx.stroke(line,
                           with: .color(.white.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
                ctx.fill(Path(ellipseIn: CGRect(x: w * m.px - 1.6, y: h * m.py - 1.6, width: 3.2, height: 3.2)),
                         with: .color(.white.opacity(0.9)))
            }
        }
        .overlay(alignment: .topLeading) {
            ZStack {
                ForEach(marks.indices, id: \.self) { i in
                    Text(marks[i].label)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color(white: 0.78))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(Rectangle().stroke(Color(white: 0.32), lineWidth: 0.7))
                        .position(x: w * marks[i].lx, y: h * marks[i].ly)
                }
            }
        }
        .opacity(vis)
    }
}
