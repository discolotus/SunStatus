import CoreGraphics
import Foundation

struct SolarArcGeometry {
    let size: CGSize
    let verticalOffset: CGFloat

    func point(at progress: Double) -> CGPoint {
        let clampedProgress = min(max(progress, 0), 1)
        let radius = min(size.width * 0.45, size.height * 0.92)
        let center = CGPoint(x: size.width / 2, y: size.height - verticalOffset)
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
