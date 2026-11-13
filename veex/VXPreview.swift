import SwiftUI

struct VXPreview: View {
    @ObservedObject var s: VXStore
    var header: Bool = true

    @State private var angle: Double = 0

    private struct Mark {
        let label: String
        let lx: CGFloat
        let ly: CGFloat
        let px: CGFloat
        let py: CGFloat
        let note: String?
    }

    private let marks: [Mark] = [
        .init(label: "DRAG", lx: 0.10, ly: 0.17, px: 0.50, py: 0.215, note: nil),
        .init(label: "PECHO", lx: 0.10, ly: 0.40, px: 0.50, py: 0.355, note: nil),
        .init(label: "BALAS MÁGICAS", lx: 0.22, ly: 0.80, px: 0.34, py: 0.63, note: "bajo tu propio riesgo")
    ]

    var body: some View {
        VStack(spacing: 4) {
            if header {
                HStack {
                    Text("VISUALIZACIÓN")
                        .font(.system(size: 10, weight: .black))
                        .tracking(4)
                        .foregroundStyle(VX.dim)
                    Spacer()
                    Text("solo referencia")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(VX.dim.opacity(0.7))
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { angle = 0 }
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
                let bw = min(w - 12, (h - 26) * 0.62)
                let bh = bw / 0.62

                ZStack {
                    Rectangle()
                        .fill(Color(white: 0.11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)

                    figure(w: bw, h: bh)
                        .position(x: w * 0.5, y: (h - 18) * 0.5)

                    overlay(w: bw, h: bh)
                        .position(x: w * 0.5, y: (h - 18) * 0.5)

                    Text("arrastra para girar")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                        .position(x: w * 0.5, y: h * 0.965)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onEnded { v in
                            let step: Double = v.translation.width > 40 ? 90 : (v.translation.width < -40 ? -90 : 0)
                            var next = angle + step
                            if next > 180 { next -= 360 }
                            if next < -180 { next += 360 }
                            withAnimation(.easeInOut(duration: 0.18)) { angle = next }
                        }
                )
            }
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
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .frame(width: w, height: h)
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
                    ctx.stroke(line, with: .color(VX.red),
                               style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    ctx.fill(Path(ellipseIn: CGRect(x: w * m.px - 2.4, y: h * m.py - 2.4,
                                                    width: 4.8, height: 4.8)),
                             with: .color(VX.red))
                }
            }

            ForEach(marks.indices, id: \.self) { i in
                VStack(spacing: 2) {
                    Text(marks[i].label)
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(VX.paper)
                    if let n = marks[i].note {
                        Text(n)
                            .font(.system(size: 7, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(VX.red)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(white: 0.13))
                .overlay(Rectangle().stroke(VX.red, lineWidth: 1.2))
                .position(x: w * marks[i].lx, y: h * marks[i].ly)
            }
        }
        .frame(width: w, height: h)
        .opacity(vis)
    }
}
