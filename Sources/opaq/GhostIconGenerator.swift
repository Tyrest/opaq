import AppKit
import SwiftUI

/// 18×18 ghost silhouette in y-up coordinates. Shared by the menu-bar template and CuteGhostView.
enum GhostShape {
    static let canvas: CGFloat = 18

    static func outline() -> CGPath {
        let path = CGMutablePath()
        let leftX: CGFloat = 3.5
        let rightX: CGFloat = 14.5
        let bodyBottomY: CGFloat = 4.0
        let headCenter = CGPoint(x: 9.0, y: 11.5)
        let headRadius: CGFloat = 5.5

        path.addArc(
            center: headCenter,
            radius: headRadius,
            startAngle: .pi,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rightX, y: bodyBottomY))

        let waveWidth = (rightX - leftX) / 3.0
        let dipY: CGFloat = 2.2
        var startX = rightX
        for _ in 0..<3 {
            let endX = startX - waveWidth
            path.addCurve(
                to: CGPoint(x: endX, y: bodyBottomY),
                control1: CGPoint(x: startX - waveWidth * 0.25, y: dipY),
                control2: CGPoint(x: startX - waveWidth * 0.75, y: dipY)
            )
            startX = endX
        }

        path.addLine(to: CGPoint(x: leftX, y: headCenter.y))
        path.closeSubpath()
        return path
    }

    static func eyes() -> (left: CGPath, right: CGPath) {
        let radius: CGFloat = 1.1
        func oval(_ center: CGPoint) -> CGPath {
            CGPath(
                ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ),
                transform: nil
            )
        }
        return (
            oval(CGPoint(x: 6.8, y: 11.2)),
            oval(CGPoint(x: 11.2, y: 11.2))
        )
    }

    /// Outline plus even-odd eye cutouts, in the 18×18 y-up box.
    static func templatePath() -> CGPath {
        let path = CGMutablePath()
        path.addPath(outline())
        let eyes = eyes()
        path.addPath(eyes.left)
        path.addPath(eyes.right)
        return path
    }

    static func swiftUIPath(_ cgPath: CGPath, in size: CGSize) -> Path {
        let scale = min(size.width, size.height) / canvas
        let transform = CGAffineTransform(translationX: 0, y: size.height)
            .scaledBy(x: scale, y: -scale)
        return Path(cgPath).applying(transform)
    }
}

enum GhostIconGenerator {
    private static var cachedImage: NSImage?

    static var menuBarGhostImage: NSImage {
        if let cached = cachedImage {
            return cached
        }

        let side = GhostShape.canvas
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scaleX = rect.width / side
            let scaleY = rect.height / side
            var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: scaleX, y: scaleY)
            guard let path = GhostShape.templatePath().copy(using: &transform) else { return false }
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }

        image.isTemplate = true
        cachedImage = image
        return image
    }
}

struct CuteGhostView: View {
    var size: CGFloat
    var isHappy: Bool

    init(size: CGFloat = 64, isHappy: Bool = true) {
        self.size = size
        self.isHappy = isHappy
    }

    var body: some View {
        Canvas { context, canvasSize in
            let outline = GhostShape.swiftUIPath(GhostShape.outline(), in: canvasSize)
            let gradient = Gradient(colors: [
                Color.blue.opacity(0.18),
                Color.purple.opacity(0.24),
            ])
            context.fill(
                outline,
                with: .linearGradient(
                    gradient,
                    startPoint: .zero,
                    endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                )
            )
            context.stroke(outline, with: .color(.primary.opacity(0.20)), lineWidth: 1)

            let eyes = GhostShape.eyes()
            context.fill(
                GhostShape.swiftUIPath(eyes.left, in: canvasSize),
                with: .color(.primary.opacity(0.75))
            )
            context.fill(
                GhostShape.swiftUIPath(eyes.right, in: canvasSize),
                with: .color(.primary.opacity(0.75))
            )

            let scale = min(canvasSize.width, canvasSize.height) / GhostShape.canvas
            let blushRadius = scale
            for centerX in [CGFloat(5.2), CGFloat(12.8)] {
                let blush = Path(
                    ellipseIn: CGRect(
                        x: centerX * scale - blushRadius,
                        y: (GhostShape.canvas - 9.8) * scale - blushRadius,
                        width: blushRadius * 2,
                        height: blushRadius * 2
                    ))
                context.fill(blush, with: .color(.pink.opacity(0.35)))
            }

            if isHappy {
                var smile = Path()
                let smileY = (GhostShape.canvas - 9.8) * scale
                smile.move(to: CGPoint(x: 8.0 * scale, y: smileY))
                smile.addQuadCurve(
                    to: CGPoint(x: 10.0 * scale, y: smileY),
                    control: CGPoint(x: 9.0 * scale, y: (GhostShape.canvas - 8.8) * scale)
                )
                context.stroke(smile, with: .color(.primary.opacity(0.60)), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
    }
}
