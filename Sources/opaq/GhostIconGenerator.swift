import AppKit
import SwiftUI

public enum GhostIconGenerator {
    private static var _cachedImage: NSImage?

    public static var menuBarGhostImage: NSImage {
        if let cached = _cachedImage {
            return cached
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.windingRule = .evenOdd

            // Outer ghost silhouette
            let leftX: CGFloat = 3.5
            let rightX: CGFloat = 14.5
            let bodyBottomY: CGFloat = 4.0
            let headCenterY: CGFloat = 11.5
            let headRadius: CGFloat = 5.5

            // Arc for top rounded head
            path.appendArc(
                withCenter: NSPoint(x: 9.0, y: headCenterY),
                radius: headRadius,
                startAngle: 180,
                endAngle: 0,
                clockwise: true
            )

            // Right side down
            path.line(to: NSPoint(x: rightX, y: bodyBottomY))

            // Wavy bottom from right (14.5) to left (3.5) with 3 scallops
            let waveWidth = (rightX - leftX) / 3.0 // ~3.667

            // Scallop 1: from 14.5 to 10.833
            let p1End = NSPoint(x: rightX - waveWidth, y: bodyBottomY)
            path.curve(to: p1End, controlPoint1: NSPoint(x: rightX - (waveWidth * 0.25), y: 2.2),
                                  controlPoint2: NSPoint(x: rightX - (waveWidth * 0.75), y: 2.2))

            // Scallop 2: from 10.833 to 7.167
            let p2End = NSPoint(x: rightX - (waveWidth * 2.0), y: bodyBottomY)
            path.curve(to: p2End, controlPoint1: NSPoint(x: p1End.x - (waveWidth * 0.25), y: 2.2),
                                  controlPoint2: NSPoint(x: p1End.x - (waveWidth * 0.75), y: 2.2))

            // Scallop 3: from 7.167 to 3.5
            let p3End = NSPoint(x: leftX, y: bodyBottomY)
            path.curve(to: p3End, controlPoint1: NSPoint(x: p2End.x - (waveWidth * 0.25), y: 2.2),
                                  controlPoint2: NSPoint(x: p2End.x - (waveWidth * 0.75), y: 2.2))

            // Left side up
            path.line(to: NSPoint(x: leftX, y: headCenterY))
            path.close()

            // Eye cutouts
            let leftEye = NSBezierPath(
                ovalIn: NSRect(x: 6.8 - 1.1, y: 11.2 - 1.1, width: 2.2, height: 2.2)
            )
            let rightEye = NSBezierPath(
                ovalIn: NSRect(x: 11.2 - 1.1, y: 11.2 - 1.1, width: 2.2, height: 2.2)
            )

            path.append(leftEye)
            path.append(rightEye)

            NSColor.black.setFill()
            path.fill()

            return true
        }

        image.isTemplate = true
        _cachedImage = image
        return image
    }
}

// MARK: - SwiftUI Cute Ghost Component

public struct CuteGhostView: View {
    public var size: CGFloat
    public var isHappy: Bool

    public init(size: CGFloat = 64, isHappy: Bool = true) {
        self.size = size
        self.isHappy = isHappy
    }

    public var body: some View {
        Group {
            if size <= 20 {
                Image(nsImage: GhostIconGenerator.menuBarGhostImage)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .foregroundStyle(.primary)
            } else {
                Canvas { context, canvasSize in
                    let w = canvasSize.width
                    let h = canvasSize.height
                    let scale = min(w, h) / 18.0

                    var path = Path()
                    let leftX = 3.5 * scale
                    let rightX = 14.5 * scale
                    let bodyBottomY = (18.0 - 4.0) * scale
                    let headCenterY = (18.0 - 11.5) * scale
                    let headRadius = 5.5 * scale

                    // Head arc
                    path.addArc(
                        center: CGPoint(x: 9.0 * scale, y: headCenterY),
                        radius: headRadius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(0),
                        clockwise: false
                    )

                    // Right side
                    path.addLine(to: CGPoint(x: rightX, y: bodyBottomY))

                    // Waves along bottom
                    let waveWidth = (rightX - leftX) / 3.0
                    let dipY = (18.0 - 2.0) * scale

                    // Scallop 1
                    let w1Mid = rightX - waveWidth * 0.5
                    path.addQuadCurve(
                        to: CGPoint(x: rightX - waveWidth, y: bodyBottomY),
                        control: CGPoint(x: w1Mid, y: dipY)
                    )
                    // Scallop 2
                    let w2Mid = rightX - waveWidth * 1.5
                    path.addQuadCurve(
                        to: CGPoint(x: rightX - waveWidth * 2.0, y: bodyBottomY),
                        control: CGPoint(x: w2Mid, y: dipY)
                    )
                    // Scallop 3
                    let w3Mid = rightX - waveWidth * 2.5
                    path.addQuadCurve(
                        to: CGPoint(x: leftX, y: bodyBottomY),
                        control: CGPoint(x: w3Mid, y: dipY)
                    )

                    path.addLine(to: CGPoint(x: leftX, y: headCenterY))
                    path.closeSubpath()

                    // Soft ambient gradient fill
                    let gradient = Gradient(colors: [
                        Color.blue.opacity(0.18),
                        Color.purple.opacity(0.24)
                    ])
                    context.fill(path, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
                    context.stroke(path, with: .color(.primary.opacity(0.20)), lineWidth: 1.0)

                    // Eyes
                    let eyeRadius = 1.15 * scale
                    let leftEyeCenter = CGPoint(x: 6.8 * scale, y: (18.0 - 11.2) * scale)
                    let rightEyeCenter = CGPoint(x: 11.2 * scale, y: (18.0 - 11.2) * scale)

                    let leftEyePath = Path(ellipseIn: CGRect(
                        x: leftEyeCenter.x - eyeRadius,
                        y: leftEyeCenter.y - eyeRadius,
                        width: eyeRadius * 2,
                        height: eyeRadius * 2
                    ))
                    let rightEyePath = Path(ellipseIn: CGRect(
                        x: rightEyeCenter.x - eyeRadius,
                        y: rightEyeCenter.y - eyeRadius,
                        width: eyeRadius * 2,
                        height: eyeRadius * 2
                    ))

                    context.fill(leftEyePath, with: .color(.primary.opacity(0.75)))
                    context.fill(rightEyePath, with: .color(.primary.opacity(0.75)))

                    // Cute subtle blush
                    let blushRadius = 1.0 * scale
                    let leftBlush = Path(ellipseIn: CGRect(
                        x: 5.2 * scale - blushRadius,
                        y: (18.0 - 9.8) * scale - blushRadius,
                        width: blushRadius * 2,
                        height: blushRadius * 2
                    ))
                    let rightBlush = Path(ellipseIn: CGRect(
                        x: 12.8 * scale - blushRadius,
                        y: (18.0 - 9.8) * scale - blushRadius,
                        width: blushRadius * 2,
                        height: blushRadius * 2
                    ))
                    context.fill(leftBlush, with: .color(.pink.opacity(0.35)))
                    context.fill(rightBlush, with: .color(.pink.opacity(0.35)))

                    // Happy smile
                    if isHappy {
                        var smile = Path()
                        let smileCenterY = (18.0 - 9.8) * scale
                        smile.move(to: CGPoint(x: 8.0 * scale, y: smileCenterY))
                        smile.addQuadCurve(
                            to: CGPoint(x: 10.0 * scale, y: smileCenterY),
                            control: CGPoint(x: 9.0 * scale, y: (18.0 - 8.8) * scale)
                        )
                        context.stroke(smile, with: .color(.primary.opacity(0.60)), lineWidth: 1.0)
                    }
                }
                .frame(width: size, height: size)
            }
        }
    }
}
