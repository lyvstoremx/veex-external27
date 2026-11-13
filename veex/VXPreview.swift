import SwiftUI

struct VXPreview: View {
    @ObservedObject var s: VXStore
    var header: Bool = true

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
        .init(label: "DRAG", lx: 0.13, ly: 0.17, px: 0.40, py: 0.21),
        .init(label: "PECHO", lx: 0.13, ly: 0.40, px: 0.38, py: 0.36),
        .init(label: "BALAS MÁGICAS", lx: 0.24, ly: 0.78, px: 0.28, py: 0.62)
    ]

    var body: some View {
        VStack(spacing: 4) {
            if header {
                HStack {
                    Text("VISUALIZACIÓN")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(4)
                        .foregroundStyle(VX.dim)
                    Spacer()
                    Text("solo referencia")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: 0.28))
                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { angle = 0; base = 0 }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(VX.dim)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }

            GeometryReader { g in
                let w = g.size.width
                let h = g.size.height
                ZStack {
                    figure(w: w, h: h)
                    overlay(w: w, h: h)
                    Text("arrastra para girar")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(white: 0.28))
                        .position(x: w * 0.5, y: h * 0.985)
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
        .shadow(color: .black.opacity(0.85), radius: 14, y: 6)
    }

    private func load(_ n: String) -> UIImage? {
        guard let p = Bundle.main.path(forResource: n, ofType: "png", inDirectory: "veex") else { return nil }
        return UIImage(contentsOfFile: p)
    }

    private func overlay(w: CGFloat, h: CGFloat) -> some View {
        let vis = max(0, 1 - abs(angle) / 55)
        return ZStack {
            Canvas { ctx, _ in
                for m in marks {
                    var line = Path()
                    line.move(to: CGPoint(x: w * m.lx, y: h * m.ly))
                    line.addLine(to: CGPoint(x: w * m.px, y: h * m.py))
                    ctx.stroke(line, with: .color(VX.red.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ctx.fill(Path(ellipseIn: CGRect(x: w * m.px - 1.8, y: h * m.py - 1.8,
                                                    width: 3.6, height: 3.6)),
                             with: .color(VX.red))
                }
            }

            ForEach(marks.indices, id: \.self) { i in
                Text(marks[i].label)
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.6)
                    .foregroundStyle(VX.paper)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75))
                    .overlay(Rectangle().stroke(VX.red, lineWidth: 1))
                    .position(x: w * marks[i].lx, y: h * marks[i].ly)
            }
        }
        .opacity(vis)
    }
}
