import SwiftUI

enum VX {
    static let ink = Color(white: 0.035)
    static let slab = Color(white: 0.085)
    static let paper = Color(white: 0.96)
    static let dim = Color(white: 0.48)
    static let red = Color(red: 0.80, green: 0.06, blue: 0.08)
}

struct VXNoise: View {
    var body: some View {
        Canvas { ctx, size in
            var g = SystemRandomNumberGenerator()
            for _ in 0..<1600 {
                let x = CGFloat.random(in: 0...size.width, using: &g)
                let y = CGFloat.random(in: 0...size.height, using: &g)
                let r = CGFloat.random(in: 0.4...1.5, using: &g)
                let a = Double.random(in: 0.02...0.09, using: &g)
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
            ForEach(0..<6, id: \.self) { i in
                Ellipse()
                    .fill(RadialGradient(colors: [VX.red.opacity(0.16), .clear],
                                         center: .center, startRadius: 0, endRadius: 170))
                    .frame(width: 340, height: 230)
                    .blur(radius: 46)
                    .rotationEffect(.degrees(Double(i) * 31))
                    .offset(x: CGFloat(i - 3) * 78, y: t ? -50 : 50)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) { t = true }
        }
    }
}

struct VXVignette: View {
    var body: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.92)],
                       center: .center, startRadius: 80, endRadius: 450)
            .allowsHitTesting(false)
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
    var depth: CGFloat = 0.05

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

    var body: some View {
        VStack(spacing: size * 0.03) {
            VXCrown()
                .stroke(VX.paper, lineWidth: max(1.1, size * 0.045))
                .frame(width: size * 0.52, height: size * 0.34)
            Text("VEEX")
                .font(.system(size: size, weight: .black))
                .italic()
                .foregroundStyle(VX.paper)
                .shadow(color: .black, radius: 0, x: size * 0.05, y: size * 0.05)
            Rectangle()
                .fill(VX.red)
                .frame(width: size * 0.62, height: max(1.2, size * 0.035))
        }
    }
}

extension View {
    func vxSlab(_ fill: Color = VX.slab) -> some View {
        background(VXTorn().fill(fill))
    }

    func vxScreen() -> some View {
        ZStack {
            VX.ink
            VXSmoke()
            VXNoise()
            VXVignette()
        }
        .ignoresSafeArea()
    }
}
