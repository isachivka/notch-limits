import CoreGraphics
import Foundation

/// Minimal SVG path-data parser (M L H V C S Q T A Z, absolute and relative),
/// enough to draw single-path icons without shipping image assets.
public enum SVGPath {
    public static func cgPath(_ d: String) -> CGPath {
        var parser = Parser(bytes: Array(d.utf8))
        return parser.parse()
    }

    struct Parser {
        let bytes: [UInt8]
        var i = 0
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: UInt8 = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func parse() -> CGPath {
            var command: UInt8 = 0
            while true {
                skipSeparators()
                guard i < bytes.count else { break }
                let b = bytes[i]
                if isCommand(b) {
                    command = b
                    i += 1
                } else if command == 0 {
                    break
                } else if command == UInt8(ascii: "M") {
                    command = UInt8(ascii: "L")
                } else if command == UInt8(ascii: "m") {
                    command = UInt8(ascii: "l")
                }
                guard execute(command) else { break }
            }
            return path
        }

        mutating func execute(_ c: UInt8) -> Bool {
            let relative = c >= UInt8(ascii: "a")
            let base = relative ? current : .zero
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: base.x + x, y: base.y + y) }

            switch c | 0x20 {
            case UInt8(ascii: "m"):
                guard let x = number(), let y = number() else { return false }
                current = point(x, y); start = current
                path.move(to: current)
                lastControl = nil
            case UInt8(ascii: "l"):
                guard let x = number(), let y = number() else { return false }
                current = point(x, y)
                path.addLine(to: current)
                lastControl = nil
            case UInt8(ascii: "h"):
                guard let x = number() else { return false }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case UInt8(ascii: "v"):
                guard let y = number() else { return false }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case UInt8(ascii: "c"):
                guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(),
                      let x = number(), let y = number() else { return false }
                let c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: point(x1, y1), control2: c2)
                lastControl = c2
            case UInt8(ascii: "s"):
                guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return false }
                let c1 = reflectedControl(cubic: true)
                let c2 = point(x2, y2)
                current = point(x, y)
                path.addCurve(to: current, control1: c1, control2: c2)
                lastControl = c2
            case UInt8(ascii: "q"):
                guard let x1 = number(), let y1 = number(), let x = number(), let y = number() else { return false }
                let c1 = point(x1, y1)
                current = point(x, y)
                path.addQuadCurve(to: current, control: c1)
                lastControl = c1
            case UInt8(ascii: "t"):
                guard let x = number(), let y = number() else { return false }
                let c1 = reflectedControl(cubic: false)
                current = point(x, y)
                path.addQuadCurve(to: current, control: c1)
                lastControl = c1
            case UInt8(ascii: "a"):
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let large = flag(), let sweep = flag(),
                      let x = number(), let y = number() else { return false }
                let end = point(x, y)
                addArc(from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                current = end
                lastControl = nil
            case UInt8(ascii: "z"):
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                return false
            }
            lastCommand = c | 0x20
            return true
        }

        func reflectedControl(cubic: Bool) -> CGPoint {
            let previous: [UInt8] = cubic ? [UInt8(ascii: "c"), UInt8(ascii: "s")] : [UInt8(ascii: "q"), UInt8(ascii: "t")]
            guard let control = lastControl, previous.contains(lastCommand) else { return current }
            return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
        }

        /// Endpoint arc → center parameterization → cubic segments (SVG spec F.6).
        func addArc(from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat,
                    rotation: CGFloat, large: Bool, sweep: Bool) {
            guard p0 != p1 else { return }
            var rx = abs(rx), ry = abs(ry)
            guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
            let phi = rotation * .pi / 180
            let cosPhi = cos(phi), sinPhi = sin(phi)
            let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
            let x1 = cosPhi * dx + sinPhi * dy
            let y1 = -sinPhi * dx + cosPhi * dy
            let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
            if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
            let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
            let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
            let coef = (large != sweep ? 1 : -1) * sqrt(max(0, num / den))
            let cxp = coef * rx * y1 / ry
            let cyp = -coef * ry * x1 / rx
            let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
            let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

            func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
                atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            }
            let ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry
            let vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry
            let theta = angle(1, 0, ux, uy)
            var delta = angle(ux, uy, vx, vy)
            if !sweep && delta > 0 { delta -= 2 * .pi }
            if sweep && delta < 0 { delta += 2 * .pi }

            let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
            let step = delta / CGFloat(segments)
            let t = 4 / 3 * tan(step / 4)
            func pointAt(_ a: CGFloat) -> CGPoint {
                CGPoint(x: cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi,
                        y: cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
            }
            func derivative(_ a: CGFloat) -> CGPoint {
                CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi,
                        y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
            }
            for k in 0..<segments {
                let a1 = theta + CGFloat(k) * step, a2 = a1 + step
                let e1 = pointAt(a1), e2 = k == segments - 1 ? p1 : pointAt(a2)
                let d1 = derivative(a1), d2 = derivative(a2)
                path.addCurve(to: e2,
                              control1: CGPoint(x: e1.x + t * d1.x, y: e1.y + t * d1.y),
                              control2: CGPoint(x: e2.x - t * d2.x, y: e2.y - t * d2.y))
            }
        }

        func isCommand(_ b: UInt8) -> Bool {
            "MmLlHhVvCcSsQqTtAaZz".utf8.contains(b)
        }

        mutating func skipSeparators() {
            while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x2C || bytes[i] == 0x0A
                || bytes[i] == 0x0D || bytes[i] == 0x09 { i += 1 }
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < bytes.count else { return nil }
            defer { i += 1 }
            switch bytes[i] {
            case UInt8(ascii: "0"): return false
            case UInt8(ascii: "1"): return true
            default: return nil
            }
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let begin = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
            var seenDot = false, seenDigit = false
            while i < bytes.count {
                let b = bytes[i]
                if b >= 0x30 && b <= 0x39 { seenDigit = true; i += 1 }
                else if b == UInt8(ascii: "."), !seenDot { seenDot = true; i += 1 }
                else { break }
            }
            if seenDigit, i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                i += 1
                if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
                while i < bytes.count, bytes[i] >= 0x30 && bytes[i] <= 0x39 { i += 1 }
            }
            guard seenDigit, let s = String(bytes: bytes[begin..<i], encoding: .ascii),
                  let value = Double(s) else { i = begin; return nil }
            return CGFloat(value)
        }
    }
}

public enum BrandIcons {
    /// OpenAI blossom from simple-icons (CC0 path data), 24×24 viewBox.
    public static let openAI = "M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"
}
