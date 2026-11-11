import SwiftUI
import UIKit

enum Wall: String, CaseIterable {
    case eye, lake, night
    var title: String {
        switch self {
        case .eye: return String(localized: "Глаз")
        case .lake: return String(localized: "Озеро")
        case .night: return String(localized: "Ночь")
        }
    }
}

/// Генеративный «глаз» из макета (drawEye): тот же генератор случайных чисел (Lehmer, seed 7),
/// те же 1400 волокон радужки. Рисуется один раз на размер экрана и кэшируется.
enum EyeRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(size: CGSize) -> UIImage {
        let w = max(1, size.width.rounded()), h = max(1, size.height.rounded())
        let key = "\(Int(w))x\(Int(h))"
        if let img = cache[key] { return img }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = min(2, UIScreen.main.scale)
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            draw(ctx.cgContext, w: w, h: h)
        }
        cache[key] = img
        return img
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a).cgColor
    }

    private static func draw(_ x: CGContext, w: CGFloat, h: CGFloat) {
        var seed: Int64 = 7
        func rnd() -> CGFloat {
            seed = (seed * 16807) % 2147483647
            return CGFloat(seed) / 2147483647
        }
        let space = CGColorSpaceCreateDeviceRGB()

        // фон
        if let g = CGGradient(colorsSpace: space, colors: [rgba(0x12, 0x0f, 0x1f, 1), rgba(0x07, 0x06, 0x0c, 1)] as CFArray, locations: [0, 1]) {
            x.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        }
        // цветные пятна
        let blobs: [(CGFloat, CGFloat, (CGFloat, CGFloat, CGFloat))] = [
            (0.15, 0.12, (169, 216, 255)), (0.9, 0.55, (255, 184, 214)), (0.2, 0.75, (195, 200, 255)), (0.75, 0.05, (220, 198, 255)),
        ]
        for b in blobs {
            let c = CGPoint(x: b.0 * w, y: b.1 * h)
            if let g = CGGradient(colorsSpace: space, colors: [rgba(b.2.0, b.2.1, b.2.2, 0.28), rgba(b.2.0, b.2.1, b.2.2, 0)] as CFArray, locations: [0, 1]) {
                x.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: w * 0.8, options: [])
            }
        }
        // радужка
        let cx = w * 0.62, cy = h * 0.27, R = max(w, h) * 0.36
        let center = CGPoint(x: cx, y: cy)
        let irisColors = [rgba(5, 4, 10, 1), rgba(0x1b, 0x18, 0x38, 1), rgba(0x58, 0x67, 0xc9, 1), rgba(0xb9, 0xc1, 0xff, 1), rgba(255, 184, 214, 0.55), rgba(255, 184, 214, 0)]
        if let g = CGGradient(colorsSpace: space, colors: irisColors as CFArray, locations: [0, 0.2 * 0.9 / 0.9, 0.38, 0.6, 0.82, 1]) {
            x.saveGState()
            x.addEllipse(in: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R))
            x.clip()
            x.drawRadialGradient(g, startCenter: center, startRadius: R * 0.1, endCenter: center, endRadius: R, options: [.drawsBeforeStartLocation])
            x.restoreGState()
        }
        // волокна
        let cols: [(CGFloat, CGFloat, CGFloat)] = [(169, 216, 255), (195, 200, 255), (255, 184, 214), (255, 255, 255), (120, 130, 230)]
        x.setLineCap(.butt)
        for _ in 0..<1400 {
            let a = rnd() * .pi * 2
            let r1 = R * (0.19 + rnd() * 0.1)
            let r2 = R * (0.45 + rnd() * 0.5)
            let bend = (rnd() - 0.5) * 0.25
            let ci = min(cols.count - 1, Int(rnd() * CGFloat(cols.count)))
            let alpha = 0.04 + rnd() * 0.16
            let lw = 0.5 + rnd() * 1.4
            let c = cols[ci]
            x.setStrokeColor(rgba(c.0, c.1, c.2, alpha))
            x.setLineWidth(lw)
            let a2: CGFloat = a + bend * 1.6
            let a1: CGFloat = a + bend
            let rm: CGFloat = (r1 + r2) / 2
            let p0 = CGPoint(x: cx + cos(a) * r1, y: cy + sin(a) * r1)
            let p2 = CGPoint(x: cx + cos(a2) * r2, y: cy + sin(a2) * r2)
            let p1 = CGPoint(x: cx + cos(a1) * rm, y: cy + sin(a1) * rm)
            x.beginPath()
            x.move(to: p0)
            x.addQuadCurve(to: p2, control: p1)
            x.strokePath()
        }
        // зрачок и блик
        x.setFillColor(rgba(6, 5, 11, 1))
        x.fillEllipse(in: CGRect(x: cx - R * 0.19, y: cy - R * 0.19, width: R * 0.38, height: R * 0.38))
        let hc = CGPoint(x: cx - R * 0.07, y: cy - R * 0.08)
        if let g = CGGradient(colorsSpace: space, colors: [rgba(255, 255, 255, 0.85), rgba(255, 255, 255, 0)] as CFArray, locations: [0, 1]) {
            x.drawRadialGradient(g, startCenter: hc, startRadius: 0, endCenter: hc, endRadius: R * 0.07, options: [])
        }
        x.setStrokeColor(rgba(255, 255, 255, 0.07))
        x.setLineWidth(1.5)
        x.strokeEllipse(in: CGRect(x: cx - R * 0.97, y: cy - R * 0.97, width: R * 1.94, height: R * 1.94))
    }
}

struct WallpaperView: View {
    let wall: Wall
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch wall {
                case .eye:
                    Image(uiImage: EyeRenderer.image(size: geo.size))
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                case .lake:
                    Image("Lake")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                case .night:
                    ZStack {
                        Color(hex: 0x0A0911)
                        RadialGradient(colors: [Color(hex: 0x2A2146), .clear], center: UnitPoint(x: 0.8, y: 0), startRadius: 0, endRadius: geo.size.width * 0.9)
                        RadialGradient(colors: [Color(hex: 0x1B2A44), .clear], center: UnitPoint(x: 0, y: 1), startRadius: 0, endRadius: geo.size.width * 0.8)
                    }
                }
                if scheme == .light {
                    // светлая тема: молочная вуаль поверх обоев — тёмный текст читается
                    LinearGradient(stops: [
                        .init(color: Color(red: 250 / 255, green: 249 / 255, blue: 253 / 255).opacity(0.78), location: 0),
                        .init(color: Color(red: 246 / 255, green: 244 / 255, blue: 251 / 255).opacity(0.88), location: 0.35),
                        .init(color: Color(red: 243 / 255, green: 241 / 255, blue: 248 / 255).opacity(0.95), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                } else {
                // затемнение (.wp-shade), чтобы текст читался на любых обоях
                LinearGradient(stops: [
                    .init(color: Color(red: 8 / 255, green: 6 / 255, blue: 14 / 255).opacity(0.25), location: 0),
                    .init(color: Color(red: 8 / 255, green: 6 / 255, blue: 14 / 255).opacity(0.55), location: 0.35),
                    .init(color: Color(red: 6 / 255, green: 5 / 255, blue: 10 / 255).opacity(0.82), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension View {
    /// Обои под экраном: каждый экран несёт их сам, поэтому переходы двигают экран целиком.
    func screenBackground(_ wall: Wall) -> some View {
        background(WallpaperView(wall: wall))
    }
}
