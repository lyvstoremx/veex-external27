import SwiftUI

enum VX {
    static let ink = Color(white: 0.06)
    static let paper = Color(white: 0.965)
    static let slab = Color(white: 1.0)
    static let dim = Color(white: 0.42)
    static let red = Color(red: 0.78, green: 0.06, blue: 0.08)
}

struct VXNoise: View {
    var body: some View {
        Canvas { ctx, size in
            var g = SystemRandomNumberGenerator()
            for _ in 0..<1500 {
                let x = CGFloat.random(in: 0...size.width, using: &g)
                let y = CGFloat.random(in: 0...size.height, using: &g)
                let r = CGFloat.random(in: 0.4...1.4, using: &g)
                let a = Double.random(in: 0.03...0.10, using: &g)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(.black.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct VXSmoke: View {
    @State private var t = false

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Ellipse()
                    .fill(RadialGradient(colors: [VX.red.opacity(0.13), .clear],
                                         center: .center, startRadius: 0, endRadius: 150))
                    .frame(width: 300, height: 200)
                    .blur(radius: 40)
                    .rotationEffect(.degrees(Double(i) * 37))
                    .offset(x: CGFloat(i - 2) * 74, y: t ? -40 : 40)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) { t = true }
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

struct VXTorn: Shape {
    var teeth: Int = 22
    var depth: CGFloat = 0.045

    func path(in r: CGRect) -> Path {
        var p = Path()
        let step = r.width / CGFloat(max(teeth, 2))
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        for i in 0...teeth {
            p.addLine(to: CGPoint(x: r.minX + CGFloat(i) * step,
                                  y: r.minY + (i % 2 == 0 ? 0 : r.height * depth)))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        for i in stride(from: teeth, through: 0, by: -1) {
            p.addLine(to: CGPoint(x: r.minX + CGFloat(i) * step,
                                  y: r.maxY - (i % 2 == 0 ? 0 : r.height * depth)))
        }
        p.closeSubpath()
        return p
    }
}

struct VXMark: View {
    var size: CGFloat = 40
    var onLight: Bool = true

    var body: some View {
        VStack(spacing: size * 0.03) {
            VXCrown()
                .stroke(onLight ? VX.ink : VX.paper, lineWidth: max(1.1, size * 0.045))
                .frame(width: size * 0.52, height: size * 0.34)
            Text("VEEX")
                .font(.system(size: size, weight: .black))
                .italic()
                .foregroundStyle(onLight ? VX.ink : VX.paper)
            Rectangle()
                .fill(VX.red)
                .frame(width: size * 0.62, height: max(1.2, size * 0.035))
        }
    }
}

extension View {
    func vxSlab(_ fill: Color = VX.slab) -> some View {
        background(VXTorn().fill(fill))
            .overlay(VXTorn().stroke(VX.ink.opacity(0.12), lineWidth: 0.8))
    }

    func vxScreen() -> some View {
        ZStack {
            VX.paper
            VXSmoke()
            VXNoise()
        }
        .ignoresSafeArea()
    }
}
