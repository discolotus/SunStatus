import CoreGraphics
import Foundation
import SunStatusCore
#if DEBUG
import SwiftUI
#endif

private enum SunlightFieldSmoothing {
    static let sampleCount = 500
    static let smoothingRadius = 4
}

#if DEBUG
private enum SunlightFieldPreviewCloudBarDesign {
    static let radiusScale: CGFloat = 0.72
    static let sampleCountMinimum = 80
    static let sampleCountMaximum = 260
    static let smoothingRadiusMultiplier = 1.0
    static let smoothingRadiusMaximum = 36

    static let featherVisibilityThreshold = 0.08
    static let lineVisibilityThreshold = 0.10
    static let occlusionIntensityThreshold = 0.18

    static let featherLineWidth: CGFloat = 8.5
    static let shadowLineWidth: CGFloat = 6.0
    static let bodyBaseLineWidth: CGFloat = 3.6
    static let bodyOcclusionLineWidthBoost: CGFloat = 1.3
    static let lineCap: CGLineCap = .round
    static let lineJoin: CGLineJoin = .round

    static let highlightRadiusOffset: CGFloat = 0.04
    static let highlightLineWidth: CGFloat = 1.1
    static let highlightOpacityMultiplier = 0.10

    static let featherWhite = 0.70
    static let featherOpacityMultiplier = 0.09

    static let shadowRed = 0.04
    static let shadowGreen = 0.04
    static let shadowBlue = 0.045
    static let shadowOpacityMultiplier = 0.34

    static let bodyClearWhite = 0.92
    static let bodyCloudWhiteDrop = 0.64
    static let bodyBaseOpacity = 0.18
    static let bodyVisibilityOpacityMultiplier = 0.74
}
#endif

struct SunlightFieldRenderer {
    struct Geometry {
        let size: CGSize
        let center: CGPoint
        let radius: CGFloat
        let startAngle: CGFloat
        let endAngle: CGFloat
        let cloudRadiusScale: CGFloat
        let cutsGroundBelowBoundaryLines: Bool
    }

    struct RenderedImage {
        let cgImage: CGImage
        let scale: CGFloat
    }

    static func render(
        geometry: Geometry,
        arcPoints: [SunArcPoint],
        fallbackBrightness: Double,
        fallbackCloudCover: Double?,
        displayScale: CGFloat
    ) -> RenderedImage? {
        let scale = min(max(displayScale, 1), 2)
        let width = max(Int((geometry.size.width * scale).rounded(.up)), 1)
        let height = max(Int((geometry.size.height * scale).rounded(.up)), 1)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let samples = fieldSamples(
            from: arcPoints,
            fallbackBrightness: fallbackBrightness,
            fallbackCloudCover: fallbackCloudCover,
            count: SunlightFieldSmoothing.sampleCount,
            smoothingRadius: SunlightFieldSmoothing.smoothingRadius
        )

        guard width > 1, height > 1, geometry.radius > 0 else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let centerX = Double(geometry.center.x)
        let centerY = Double(geometry.center.y)
        let radius = Double(geometry.radius)
        let startAngle = Double(geometry.startAngle)
        let endAngle = Double(geometry.endAngle)
        let cloudRadius = radius * Double(geometry.cloudRadiusScale)
        let outerFeather = max(1.4, 2.2 / Double(scale))
        let boundaryFeather = max(1.2, 2.0 / Double(scale))

        for pixelY in 0..<height {
            let y = (Double(pixelY) + 0.5) / Double(scale)

            for pixelX in 0..<width {
                let x = (Double(pixelX) + 0.5) / Double(scale)
                let dx = x - centerX
                let dy = y - centerY
                let distance = hypot(dx, dy)

                guard distance <= radius else {
                    continue
                }

                let rawAngle = atan2(dy, dx)
                guard let progress = progress(
                    for: rawAngle,
                    startAngle: startAngle,
                    endAngle: endAngle
                ) else {
                    continue
                }

                let groundMask = groundMask(
                    x: x,
                    y: y,
                    geometry: geometry,
                    feather: boundaryFeather
                )
                guard groundMask > 0 else {
                    continue
                }

                let fieldSample = sample(at: progress, in: samples)
                let radialProgress = min(max(distance / radius, 0), 1)
                let radialEdgeMask = 1 - smootherStep((distance - (radius - outerFeather)) / outerFeather)
                let angleEdgeDistance = min(progress, 1 - progress) * (endAngle - startAngle) * radius
                let angleEdgeMask = min(max(angleEdgeDistance / boundaryFeather, 0), 1)
                let mask = min(radialEdgeMask, min(angleEdgeMask, groundMask))

                guard mask > 0 else {
                    continue
                }

                let color = color(
                    progress: progress,
                    radialProgress: radialProgress,
                    distance: distance,
                    cloudRadius: cloudRadius,
                    cloudRadiusProgress: cloudRadius / radius,
                    brightness: fieldSample.brightness,
                    cloudCover: fieldSample.cloudCover
                )
                write(
                    color: color,
                    alphaMultiplier: mask,
                    to: &pixels,
                    offset: (pixelY * bytesPerRow) + (pixelX * bytesPerPixel)
                )
            }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return RenderedImage(cgImage: image, scale: scale)
    }

    private struct FieldSample {
        let progress: Double
        let brightness: Double
        let cloudCover: Double
    }

    private struct FieldColor {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        func blended(to target: FieldColor, amount: Double) -> FieldColor {
            let t = min(max(amount, 0), 1)
            return FieldColor(
                red: red + ((target.red - red) * t),
                green: green + ((target.green - green) * t),
                blue: blue + ((target.blue - blue) * t),
                alpha: alpha + ((target.alpha - alpha) * t)
            )
        }
    }

    private static func fieldSamples(
        from points: [SunArcPoint],
        fallbackBrightness: Double,
        fallbackCloudCover: Double?,
        count: Int,
        smoothingRadius: Int
    ) -> [FieldSample] {
        let sortedPoints = points.sorted { $0.progress < $1.progress }
        let totalCount = max(count, 2)
        let fallbackCloudCover = min(max(fallbackCloudCover ?? 0, 0), 1)
        let fallbackBrightness = min(max(fallbackBrightness, 0), 1)
        let brightnessCurve = SmoothProgressCurve(
            points: sortedPoints,
            fallback: fallbackBrightness,
            value: \.brightnessScore
        )
        let cloudCurve = SmoothProgressCurve(
            points: sortedPoints,
            fallback: fallbackCloudCover,
            value: \.cloudCover
        )

        let rawSamples = (0...totalCount).map { index in
            let progress = Double(index) / Double(totalCount)
            return FieldSample(
                progress: progress,
                brightness: brightnessCurve.value(at: progress),
                cloudCover: cloudCurve.value(at: progress)
            )
        }

        return smooth(samples: rawSamples, radius: smoothingRadius)
    }

    private static func smooth(samples: [FieldSample], radius: Int) -> [FieldSample] {
        guard radius > 0, samples.count > 2 else {
            return samples
        }

        return samples.indices.map { index in
            let lowerBound = max(samples.startIndex, index - radius)
            let upperBound = min(samples.index(before: samples.endIndex), index + radius)
            var weightedBrightness = 0.0
            var weightedCloudCover = 0.0
            var totalWeight = 0.0

            for neighborIndex in lowerBound...upperBound {
                let distance = abs(neighborIndex - index)
                let normalizedDistance = Double(distance) / Double(radius + 1)
                let weight = 1 - (normalizedDistance * normalizedDistance)
                weightedBrightness += samples[neighborIndex].brightness * weight
                weightedCloudCover += samples[neighborIndex].cloudCover * weight
                totalWeight += weight
            }

            guard totalWeight > 0 else {
                return samples[index]
            }

            return FieldSample(
                progress: samples[index].progress,
                brightness: weightedBrightness / totalWeight,
                cloudCover: weightedCloudCover / totalWeight
            )
        }
    }

    private static func sample(at progress: Double, in samples: [FieldSample]) -> FieldSample {
        guard let first = samples.first else {
            return FieldSample(progress: progress, brightness: 0.5, cloudCover: 0)
        }

        let clampedProgress = min(max(progress, 0), 1)
        guard let last = samples.last, samples.count > 1 else {
            return FieldSample(progress: clampedProgress, brightness: first.brightness, cloudCover: first.cloudCover)
        }

        if clampedProgress <= first.progress {
            return first
        }

        if clampedProgress >= last.progress {
            return last
        }

        var lowerIndex = samples.startIndex
        var upperIndex = samples.index(before: samples.endIndex)

        while samples.index(after: lowerIndex) < upperIndex {
            let distance = samples.distance(from: lowerIndex, to: upperIndex)
            let middleIndex = samples.index(lowerIndex, offsetBy: distance / 2)

            if samples[middleIndex].progress < clampedProgress {
                lowerIndex = middleIndex
            } else {
                upperIndex = middleIndex
            }
        }

        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]
        let span = upper.progress - lower.progress
        guard span > 0 else {
            return upper
        }

        let ratio = min(max((clampedProgress - lower.progress) / span, 0), 1)
        return FieldSample(
            progress: clampedProgress,
            brightness: lower.brightness + ((upper.brightness - lower.brightness) * ratio),
            cloudCover: lower.cloudCover + ((upper.cloudCover - lower.cloudCover) * ratio)
        )
    }

    private static func progress(for rawAngle: Double, startAngle: Double, endAngle: Double) -> Double? {
        let candidates = [
            rawAngle - (2 * Double.pi),
            rawAngle,
            rawAngle + (2 * Double.pi)
        ]
        let epsilon = 0.000_001

        guard let unwrapped = candidates.first(where: { $0 >= startAngle - epsilon && $0 <= endAngle + epsilon }) else {
            return nil
        }

        let span = endAngle - startAngle
        guard span > 0 else {
            return nil
        }

        return min(max((unwrapped - startAngle) / span, 0), 1)
    }

    private static func groundMask(
        x: Double,
        y: Double,
        geometry: Geometry,
        feather: Double
    ) -> Double {
        guard geometry.cutsGroundBelowBoundaryLines else {
            return 1
        }

        let left = point(
            center: geometry.center,
            radius: geometry.radius,
            angle: geometry.startAngle
        )
        let right = point(
            center: geometry.center,
            radius: geometry.radius,
            angle: geometry.endAngle
        )
        let center = geometry.center
        let boundaryY: Double

        if x <= Double(center.x) {
            boundaryY = interpolatedY(x: x, from: left, to: center)
        } else {
            boundaryY = interpolatedY(x: x, from: center, to: right)
        }

        return smootherStep((boundaryY - y) / feather)
    }

    private static func interpolatedY(x: Double, from start: CGPoint, to end: CGPoint) -> Double {
        let startX = Double(start.x)
        let endX = Double(end.x)
        let span = endX - startX

        guard abs(span) > 0.000_001 else {
            return min(Double(start.y), Double(end.y))
        }

        let ratio = min(max((x - startX) / span, 0), 1)
        return Double(start.y) + ((Double(end.y) - Double(start.y)) * ratio)
    }

    private static func color(
        progress: Double,
        radialProgress: Double,
        distance: Double,
        cloudRadius: Double,
        cloudRadiusProgress: Double,
        brightness: Double,
        cloudCover: Double
    ) -> FieldColor {
        let noonBias = 1 - abs((progress * 2) - 1)
        let radialLift = 1 - pow(1 - radialProgress, 1.4)
        let clear = FieldColor(red: 1.00, green: 0.84, blue: 0.08, alpha: 0.52)
        let warm = FieldColor(red: 1.00, green: 0.52, blue: 0.06, alpha: 0.48)
        let bright = FieldColor(red: 1.00, green: 0.91, blue: 0.22, alpha: 0.60)
        let shadow = FieldColor(red: 0.030, green: 0.034, blue: 0.030, alpha: 0.76)

        var color = warm.blended(to: clear, amount: 0.34 + (noonBias * 0.52))
        color = color.blended(to: bright, amount: 0.12 + (brightness * 0.18) + (radialLift * 0.10))
        color.alpha = 0.34 + (brightness * 0.18) + (radialProgress * 0.22)

        let cloudIntensity = smoothRamp(cloudCover, threshold: 0.16)
        let cloudFeather = max(cloudRadius * 0.055, 4.5)
        let belowCloud = 1 - smootherStep((distance - (cloudRadius - cloudFeather)) / (cloudFeather * 1.35))
        let aboveCloud = smootherStep((distance - (cloudRadius - (cloudFeather * 0.25))) / cloudFeather)
        let occlusion = cloudIntensity * belowCloud
        let deepCore = occlusion * pow(max(1 - (radialProgress / max(cloudRadiusProgress, 0.01)), 0), 0.75)
        let shadowAmount = min(0.88, (occlusion * 0.62) + (deepCore * 0.26))
        let topGlow = cloudIntensity * aboveCloud * (1 - smootherStep((radialProgress - 0.96) / 0.05))

        color = color.blended(to: shadow, amount: shadowAmount)
        color = color.blended(to: bright, amount: topGlow * 0.18)
        color.alpha = min(max(color.alpha + (occlusion * 0.24) + (topGlow * 0.10), 0), 0.92)

        return color
    }

    private static func write(
        color: FieldColor,
        alphaMultiplier: Double,
        to pixels: inout [UInt8],
        offset: Int
    ) {
        let alpha = min(max(color.alpha * alphaMultiplier, 0), 1)
        pixels[offset] = byte(color.red * alpha)
        pixels[offset + 1] = byte(color.green * alpha)
        pixels[offset + 2] = byte(color.blue * alpha)
        pixels[offset + 3] = byte(alpha)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(max((value * 255).rounded(), 0), 255))
    }

    private static func smoothRamp(_ value: Double, threshold: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        let clampedThreshold = min(max(threshold, 0), 0.98)
        guard clamped > clampedThreshold else {
            return 0
        }

        return smootherStep((clamped - clampedThreshold) / (1 - clampedThreshold))
    }

    private static func smootherStep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10)
    }

    private static func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

/// Monotone cubic interpolation for forecast samples. Each interval is equivalent
/// to a cubic Bezier segment, but the slope limiter avoids cloud-cover overshoot.
struct SmoothProgressCurve {
    struct Point {
        let progress: Double
        let value: Double
    }

    private let fallback: Double
    private let points: [Point]
    private let slopes: [Double]

    init(
        points sourcePoints: [SunArcPoint],
        fallback: Double,
        value: KeyPath<SunArcPoint, Double?>
    ) {
        let normalizedPoints = Self.uniqueSortedPoints(
            sourcePoints.map {
                Point(
                    progress: Self.clamp($0.progress),
                    value: Self.clamp($0[keyPath: value] ?? fallback)
                )
            }
        )

        self.fallback = Self.clamp(fallback)
        self.points = normalizedPoints
        self.slopes = Self.slopes(for: normalizedPoints)
    }

    func value(at progress: Double) -> Double {
        guard let first = points.first else {
            return fallback
        }

        let clampedProgress = Self.clamp(progress)
        guard points.count > 1 else {
            return first.value
        }

        if clampedProgress <= first.progress {
            return first.value
        }

        for index in 0..<points.count - 1 where clampedProgress <= points[index + 1].progress {
            return value(at: clampedProgress, lowerIndex: index)
        }

        return points.last?.value ?? fallback
    }

    private func value(at progress: Double, lowerIndex: Int) -> Double {
        let lower = points[lowerIndex]
        let upper = points[lowerIndex + 1]
        let span = upper.progress - lower.progress
        guard span > 0 else {
            return upper.value
        }

        let t = (progress - lower.progress) / span
        let t2 = t * t
        let t3 = t2 * t
        let h00 = (2 * t3) - (3 * t2) + 1
        let h10 = t3 - (2 * t2) + t
        let h01 = (-2 * t3) + (3 * t2)
        let h11 = t3 - t2
        let value = (h00 * lower.value)
            + (h10 * span * slopes[lowerIndex])
            + (h01 * upper.value)
            + (h11 * span * slopes[lowerIndex + 1])

        return Self.clamp(value)
    }

    private static func uniqueSortedPoints(_ sourcePoints: [Point]) -> [Point] {
        let sorted = sourcePoints.sorted { $0.progress < $1.progress }
        var unique: [Point] = []

        for point in sorted {
            if let last = unique.last, abs(last.progress - point.progress) < 0.000_001 {
                unique[unique.count - 1] = point
            } else {
                unique.append(point)
            }
        }

        return unique
    }

    private static func slopes(for points: [Point]) -> [Double] {
        guard points.count > 1 else {
            return points.map { _ in 0 }
        }

        let pairedPoints = Array(zip(points, points.dropFirst()))
        let spans = pairedPoints.map { pair in pair.1.progress - pair.0.progress }
        let deltas = zip(pairedPoints, spans).map { element in
            let pair = element.0
            let span = element.1
            return span > 0 ? (pair.1.value - pair.0.value) / span : 0
        }

        guard points.count > 2 else {
            return [deltas[0], deltas[0]]
        }

        return points.indices.map { index in
            if index == points.startIndex {
                return deltas[0]
            }

            if index == points.index(before: points.endIndex) {
                return deltas[deltas.index(before: deltas.endIndex)]
            }

            let previousDelta = deltas[index - 1]
            let nextDelta = deltas[index]
            guard previousDelta * nextDelta > 0 else {
                return 0
            }

            let previousSpan = spans[index - 1]
            let nextSpan = spans[index]
            let previousWeight = (2 * nextSpan) + previousSpan
            let nextWeight = nextSpan + (2 * previousSpan)
            return (previousWeight + nextWeight)
                / ((previousWeight / previousDelta) + (nextWeight / nextDelta))
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

#if DEBUG
private struct SunlightFieldRendererPreviewBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sunlight Field Renderer")
                    .font(.title2.weight(.semibold))

                Spacer()

                Text("samples \(SunlightFieldSmoothing.sampleCount)  smoothing \(SunlightFieldSmoothing.smoothingRadius)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                SunlightFieldRendererPreviewCard(
                    title: "Clear morning",
                    status: SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus(hour: 8, minute: 30)
                )

                SunlightFieldRendererPreviewCard(
                    title: "Cloudy afternoon",
                    status: SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus(hour: 14, minute: 30)
                )

                SunlightFieldRendererPreviewCard(
                    title: "Night next day",
                    status: SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus(hour: 22, minute: 15)
                )
            }
        }
        .padding(24)
        .background(Color.primary.opacity(0.035))
    }
}

private struct SunlightFieldRendererPreviewCard: View {
    @Environment(\.displayScale) private var displayScale

    let title: String
    let status: DaylightStatus

    private let previewSize = CGSize(width: 244, height: 154)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ZStack {
                fieldImage
                referenceOverlay
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Text("light \(percent(status.brightness.score))")
                Text("clouds \(percent(status.brightness.cloudCover))")
                Spacer(minLength: 0)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 272, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var fieldImage: some View {
        if let rendered = renderedImage {
            Image(decorative: rendered.cgImage, scale: rendered.scale, orientation: .up)
                .resizable()
                .interpolation(.high)
                .frame(width: previewSize.width, height: previewSize.height)
        } else {
            Color.red.opacity(0.16)
        }
    }

    private var referenceOverlay: some View {
        Canvas { context, size in
            let geometry = SunlightFieldRendererPreviewGeometry(
                size: size,
                status: status,
                cloudRadiusScale: SunlightFieldPreviewCloudBarDesign.radiusScale
            )

            context.stroke(
                geometry.fanPath,
                with: .color(.orange.opacity(0.16)),
                lineWidth: 1
            )

            var sunriseLine = Path()
            sunriseLine.move(to: geometry.center)
            sunriseLine.addLine(to: geometry.point(at: 0))
            context.stroke(sunriseLine, with: .color(.orange.opacity(0.48)), lineWidth: 1)

            var sunsetLine = Path()
            sunsetLine.move(to: geometry.center)
            sunsetLine.addLine(to: geometry.point(at: 1))
            context.stroke(sunsetLine, with: .color(.orange.opacity(0.48)), lineWidth: 1)

            var arcReference = Path()
            arcReference.addLines(geometry.points(from: 0, through: 1, steps: 96))
            context.stroke(
                arcReference,
                with: .linearGradient(
                    Gradient(colors: [.orange.opacity(0.80), .yellow.opacity(0.86)]),
                    startPoint: geometry.point(at: 0),
                    endPoint: geometry.point(at: 1)
                ),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )

            drawCloudCoverBar(in: context, geometry: geometry)

            if let progress = status.solar.daylightProgress {
                let sunPoint = geometry.point(at: progress)
                context.fill(
                    Path(ellipseIn: CGRect(x: sunPoint.x - 5, y: sunPoint.y - 5, width: 10, height: 10)),
                    with: .color(.yellow)
                )
                context.stroke(
                    Path(ellipseIn: CGRect(x: sunPoint.x - 5, y: sunPoint.y - 5, width: 10, height: 10)),
                    with: .color(.orange),
                    lineWidth: 1.5
                )
            }
        }
    }

    private func drawCloudCoverBar(
        in context: GraphicsContext,
        geometry: SunlightFieldRendererPreviewGeometry
    ) {
        let samples = cloudBarSamples()
        guard samples.contains(where: { cloudFeatherOpacity(for: $0.cloudCover) > 0 }) else {
            return
        }

        for pair in zip(samples, samples.dropFirst()) {
            let cloudCover = (pair.0.cloudCover + pair.1.cloudCover) / 2
            let featherOpacity = cloudFeatherOpacity(for: cloudCover)
            guard featherOpacity > 0 else {
                continue
            }

            var segment = Path()
            segment.move(to: geometry.point(at: pair.0.progress, radiusScale: SunlightFieldPreviewCloudBarDesign.radiusScale))
            segment.addLine(to: geometry.point(at: pair.1.progress, radiusScale: SunlightFieldPreviewCloudBarDesign.radiusScale))

            context.stroke(
                segment,
                with: .color(cloudFeatherColor(for: cloudCover)),
                style: cloudBarStroke(lineWidth: SunlightFieldPreviewCloudBarDesign.featherLineWidth)
            )

            let lineOpacity = cloudLineOpacity(for: cloudCover)
            guard lineOpacity > 0 else {
                continue
            }

            context.stroke(
                segment,
                with: .color(cloudShadowColor(for: cloudCover)),
                style: cloudBarStroke(lineWidth: SunlightFieldPreviewCloudBarDesign.shadowLineWidth)
            )
            context.stroke(
                segment,
                with: .color(cloudBodyColor(for: cloudCover)),
                style: cloudBarStroke(lineWidth: cloudBodyLineWidth(for: cloudCover))
            )

            let highlightRadiusScale = max(
                SunlightFieldPreviewCloudBarDesign.radiusScale - SunlightFieldPreviewCloudBarDesign.highlightRadiusOffset,
                0
            )
            var highlight = Path()
            highlight.move(to: geometry.point(at: pair.0.progress, radiusScale: highlightRadiusScale))
            highlight.addLine(to: geometry.point(at: pair.1.progress, radiusScale: highlightRadiusScale))
            context.stroke(
                highlight,
                with: .color(.white.opacity(SunlightFieldPreviewCloudBarDesign.highlightOpacityMultiplier * lineOpacity)),
                style: cloudBarStroke(lineWidth: SunlightFieldPreviewCloudBarDesign.highlightLineWidth)
            )
        }
    }

    private func cloudBarStroke(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(
            lineWidth: lineWidth,
            lineCap: SunlightFieldPreviewCloudBarDesign.lineCap,
            lineJoin: SunlightFieldPreviewCloudBarDesign.lineJoin
        )
    }

    private struct CloudBarSample {
        let progress: Double
        let cloudCover: Double
    }

    private func cloudBarSamples() -> [CloudBarSample] {
        let points = status.arcPoints.sorted { $0.progress < $1.progress }
        let fallback = min(max(status.brightness.cloudCover ?? 0, 0), 1)
        let sampleCount = min(
            max(SunlightFieldSmoothing.sampleCount, SunlightFieldPreviewCloudBarDesign.sampleCountMinimum),
            SunlightFieldPreviewCloudBarDesign.sampleCountMaximum
        )
        let cloudCurve = SmoothProgressCurve(
            points: points,
            fallback: fallback,
            value: \.cloudCover
        )
        let rawSamples = (0...sampleCount).map { index in
            let progress = Double(index) / Double(sampleCount)
            return CloudBarSample(
                progress: progress,
                cloudCover: cloudCurve.value(at: progress)
            )
        }

        return smoothCloudBarSamples(rawSamples)
    }

    private func smoothCloudBarSamples(_ samples: [CloudBarSample]) -> [CloudBarSample] {
        let adjustedRadius = Int((Double(SunlightFieldSmoothing.smoothingRadius) * SunlightFieldPreviewCloudBarDesign.smoothingRadiusMultiplier).rounded())
        let radius = min(max(adjustedRadius, 0), SunlightFieldPreviewCloudBarDesign.smoothingRadiusMaximum)
        guard radius > 0, samples.count > 2 else {
            return samples
        }

        return samples.indices.map { index in
            let lowerBound = max(samples.startIndex, index - radius)
            let upperBound = min(samples.index(before: samples.endIndex), index + radius)
            var weightedCloudCover = 0.0
            var totalWeight = 0.0

            for neighborIndex in lowerBound...upperBound {
                let distance = abs(neighborIndex - index)
                let normalizedDistance = Double(distance) / Double(radius + 1)
                let weight = 1 - (normalizedDistance * normalizedDistance)
                weightedCloudCover += samples[neighborIndex].cloudCover * weight
                totalWeight += weight
            }

            guard totalWeight > 0 else {
                return samples[index]
            }

            return CloudBarSample(
                progress: samples[index].progress,
                cloudCover: weightedCloudCover / totalWeight
            )
        }
    }

    private func cloudFeatherOpacity(for cloudCover: Double) -> Double {
        smoothRamp(cloudCover, threshold: SunlightFieldPreviewCloudBarDesign.featherVisibilityThreshold)
    }

    private func cloudLineOpacity(for cloudCover: Double) -> Double {
        smoothRamp(cloudCover, threshold: SunlightFieldPreviewCloudBarDesign.lineVisibilityThreshold)
    }

    private func cloudOcclusionIntensity(for cloudCover: Double) -> Double {
        smoothRamp(cloudCover, threshold: SunlightFieldPreviewCloudBarDesign.occlusionIntensityThreshold)
    }

    private func cloudFeatherColor(for cloudCover: Double) -> Color {
        Color(white: SunlightFieldPreviewCloudBarDesign.featherWhite)
            .opacity(SunlightFieldPreviewCloudBarDesign.featherOpacityMultiplier * cloudFeatherOpacity(for: cloudCover))
    }

    private func cloudShadowColor(for cloudCover: Double) -> Color {
        Color(
            red: SunlightFieldPreviewCloudBarDesign.shadowRed,
            green: SunlightFieldPreviewCloudBarDesign.shadowGreen,
            blue: SunlightFieldPreviewCloudBarDesign.shadowBlue
        )
        .opacity(SunlightFieldPreviewCloudBarDesign.shadowOpacityMultiplier * cloudLineOpacity(for: cloudCover))
    }

    private func cloudBodyColor(for cloudCover: Double) -> Color {
        let clamped = min(max(cloudCover, 0), 1)
        let visibility = cloudLineOpacity(for: clamped)
        let white = SunlightFieldPreviewCloudBarDesign.bodyClearWhite
            - (clamped * SunlightFieldPreviewCloudBarDesign.bodyCloudWhiteDrop)
        let opacity = SunlightFieldPreviewCloudBarDesign.bodyBaseOpacity
            + (visibility * SunlightFieldPreviewCloudBarDesign.bodyVisibilityOpacityMultiplier)
        return Color(white: white).opacity(opacity)
    }

    private func cloudBodyLineWidth(for cloudCover: Double) -> CGFloat {
        SunlightFieldPreviewCloudBarDesign.bodyBaseLineWidth
            + CGFloat(cloudOcclusionIntensity(for: cloudCover)) * SunlightFieldPreviewCloudBarDesign.bodyOcclusionLineWidthBoost
    }

    private func smoothRamp(_ value: Double, threshold: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        let clampedThreshold = min(max(threshold, 0), 0.98)
        guard clamped > clampedThreshold else {
            return 0
        }

        return smootherStep((clamped - clampedThreshold) / (1 - clampedThreshold))
    }

    private func smootherStep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10)
    }

    private var renderedImage: SunlightFieldRenderer.RenderedImage? {
        let geometry = SunlightFieldRendererPreviewGeometry(
            size: previewSize,
            status: status,
            cloudRadiusScale: SunlightFieldPreviewCloudBarDesign.radiusScale
        )

        return SunlightFieldRenderer.render(
            geometry: geometry.rendererGeometry,
            arcPoints: status.arcPoints,
            fallbackBrightness: status.brightness.score,
            fallbackCloudCover: status.brightness.cloudCover,
            displayScale: min(displayScale, 1)
        )
    }

    private func percent(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return "\(Int((value * 100).rounded()))%"
    }
}

private struct SunlightFieldRendererPreviewGeometry {
    let size: CGSize
    let dayFraction: Double
    let cloudRadiusScale: CGFloat

    init(size: CGSize, status: DaylightStatus, cloudRadiusScale: CGFloat) {
        self.size = size
        self.dayFraction = Self.daylightFraction(status: status)
        self.cloudRadiusScale = cloudRadiusScale
    }

    var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.58)
    }

    var radius: CGFloat {
        min(size.width * 0.44, size.height * 0.43)
    }

    var dayAngle: CGFloat {
        CGFloat(min(max(dayFraction, 0.02), 0.98) * 2 * .pi)
    }

    var sunriseAngle: CGFloat {
        CGFloat(-Double.pi / 2) - (dayAngle / 2)
    }

    var sunsetAngle: CGFloat {
        sunriseAngle + dayAngle
    }

    var rendererGeometry: SunlightFieldRenderer.Geometry {
        SunlightFieldRenderer.Geometry(
            size: size,
            center: center,
            radius: radius,
            startAngle: sunriseAngle,
            endAngle: sunsetAngle,
            cloudRadiusScale: cloudRadiusScale,
            cutsGroundBelowBoundaryLines: true
        )
    }

    var fanPath: Path {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(at: 0))
        path.addLines(points(from: 0, through: 1, steps: 96))
        path.closeSubpath()
        return path
    }

    func point(at progress: Double, radiusScale: CGFloat = 1) -> CGPoint {
        let angle = sunriseAngle + (CGFloat(min(max(progress, 0), 1)) * dayAngle)
        let scaledRadius = radius * min(max(radiusScale, 0), 1)
        return CGPoint(
            x: center.x + cos(angle) * scaledRadius,
            y: center.y + sin(angle) * scaledRadius
        )
    }

    func points(
        from start: Double,
        through end: Double,
        radiusScale: CGFloat = 1,
        steps: Int
    ) -> [CGPoint] {
        let clampedStart = min(max(start, 0), 1)
        let clampedEnd = min(max(end, 0), 1)
        let totalSteps = max(steps, 1)

        return (0...totalSteps).map { index in
            let progress = clampedStart + ((clampedEnd - clampedStart) * Double(index) / Double(totalSteps))
            return point(at: progress, radiusScale: radiusScale)
        }
    }

    private static func daylightFraction(status: DaylightStatus) -> Double {
        let sortedPoints = status.arcPoints.sorted { $0.progress < $1.progress }
        let sunrise = sortedPoints.first?.date ?? status.solar.sunrise
        let sunset = sortedPoints.last?.date ?? status.solar.sunset

        guard let sunrise, let sunset, sunset > sunrise else {
            return 0.5
        }

        return min(max(sunset.timeIntervalSince(sunrise) / 86_400, 0.02), 0.98)
    }
}

#Preview("Sunlight Field Renderer Tuning", traits: .sizeThatFitsLayout) {
    SunlightFieldRendererPreviewBoard()
}
#endif
