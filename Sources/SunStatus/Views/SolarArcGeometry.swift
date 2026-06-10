import CoreGraphics
import Foundation

struct SolarArcGeometry {
    let size: CGSize
    let verticalOffset: CGFloat

    func point(at progress: Double) -> CGPoint {
        point(at: progress, radiusScale: 1)
    }

    func point(at progress: Double, radiusScale: CGFloat) -> CGPoint {
        let clampedProgress = min(max(progress, 0), 1)
        let clampedRadiusScale = min(max(radiusScale, 0), 1)
        let center = CGPoint(x: size.width / 2, y: size.height - verticalOffset)
        let topPadding = max(size.height * 0.06, 4)
        let radius = min(size.width * 0.45, max(center.y - topPadding, 1)) * clampedRadiusScale
        let angle = .pi - (clampedProgress * .pi)

        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y - sin(angle) * radius
        )
    }

    func points(from start: Double, through end: Double, steps: Int) -> [CGPoint] {
        let clampedStart = min(max(start, 0), 1)
        let clampedEnd = min(max(end, 0), 1)
        let totalSteps = max(steps, 1)

        return (0...totalSteps).map { index in
            let progress = clampedStart + ((clampedEnd - clampedStart) * Double(index) / Double(totalSteps))
            return point(at: progress)
        }
    }
}
