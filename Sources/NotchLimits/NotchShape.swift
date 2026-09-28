import NotchLimitsCore
import SwiftUI

/// The notch silhouette: concave "shoulders" at the top that melt into the
/// menu bar, rounded corners at the bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Anthropic-style starburst, drawn so we ship no brand assets.
struct Starburst: Shape {
    var rays = 10

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<rays {
            let a = CGFloat(i) / CGFloat(rays) * .pi * 2 - .pi / 2
            let w = r * 0.13
            let dir = CGPoint(x: cos(a), y: sin(a))
            let n = CGPoint(x: -dir.y, y: dir.x)
            let tip = CGPoint(x: c.x + dir.x * r, y: c.y + dir.y * r)
            p.move(to: CGPoint(x: c.x + n.x * w * 0.4, y: c.y + n.y * w * 0.4))
            p.addLine(to: CGPoint(x: tip.x + n.x * w * 0.5, y: tip.y + n.y * w * 0.5))
            p.addLine(to: CGPoint(x: tip.x - n.x * w * 0.5, y: tip.y - n.y * w * 0.5))
            p.addLine(to: CGPoint(x: c.x - n.x * w * 0.4, y: c.y - n.y * w * 0.4))
            p.closeSubpath()
        }
        return p
    }
}

/// OpenAI blossom, drawn from path data and scaled to fit.
struct OpenAIMark: Shape {
    private static let icon = SVGPath.cgPath(BrandIcons.openAI)

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        var transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Path(Self.icon.copy(using: &transform) ?? Self.icon)
    }
}
