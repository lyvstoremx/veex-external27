import SwiftUI

enum VX {
    static let ink = Color(white: 0.075)
    static let slab = Color(white: 0.125)
    static let paper = Color(white: 0.93)
    static let dim = Color(white: 0.50)
    static let line = Color(white: 0.22)
    static let red = Color(red: 0.86, green: 0.11, blue: 0.13)
    static let green = Color(red: 0.13, green: 0.70, blue: 0.36)
}

struct VXNoise: View {
    var body: some View {
        Canvas { ctx, size in
            var g = SystemRandomNumberGenerator()
            for _ in 0..<900 {
                let x = CGFloat.random(in: 0...size.width, using: &g)
                let y = CGFloat.random(in: 0...size.height, using: &g)
                let r = CGFloat.random(in: 0.4...1.2, using: &g)
                let a = Double.random(in: 0.02...0.07, using: &g)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct VXSmoke: View {
    @State private var t = false

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Ellipse()
                    .fill(RadialGradient(colors: [VX.red.opacity(0.09), .clear],
                                         center: .center, startRadius: 0, endRadius: 170))
                    .frame(width: 330, height: 220)
                    .blur(radius: 55)
                    .rotationEffect(.degrees(Double(i) * 41))
                    .offset(x: CGFloat(i - 2) * 80, y: t ? -34 : 34)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { t = true }
        }
    }
}

struct VXCrown: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.36))
        p.addLine(to: CGPoint(x: w * 0.25, y: h * 0.64))
        p.addLine(to: CGPoint(x: w * 0.5, y: 0))
        p.addLine(to: CGPoint(x: w * 0.75, y: h * 0.64))
        p.addLine(to: CGPoint(x: w, y: h * 0.36))
        p.addLine(to: CGPoint(x: w, y: h))
        return p
    }
}

struct VXMark: View {
    var size: CGFloat = 40

    var body: some View {
        VStack(spacing: size * 0.05) {
            VXCrown()
                .stroke(VX.paper, lineWidth: max(1.1, size * 0.04))
                .frame(width: size * 0.5, height: size * 0.32)
            Text("VEEX")
                .font(.system(size: size, weight: .black))
                .italic()
                .foregroundStyle(VX.paper)
            Rectangle()
                .fill(VX.red)
                .frame(width: size * 0.6, height: max(1.2, size * 0.03))
        }
    }
}

extension View {
    func vxCard(_ fill: Color = VX.slab) -> some View {
        background(fill)
            .overlay(Rectangle().stroke(VX.line, lineWidth: 1))
    }

    func vxHair() -> some View {
        overlay(alignment: .top) {
            Rectangle().fill(VX.line).frame(height: 1)
        }
    }
}
