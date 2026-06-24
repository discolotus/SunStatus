import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif

public enum SolarArcDaylightLayout: Sendable {
    case normalized
    case proportional
}

private enum CloudTransitionSmoothing {
    static let lineSampleCount = 256
    static let compactLineSampleCount = 192
    static let nightShadeSampleCount = 192
    static let lineSmoothingRadius = 24
    static let compactLineSmoothingRadius = 20
    static let nightShadeSmoothingRadius = 20
}

public struct SolarArcView: View {
    @Environment(\.displayScale) private var displayScale

    private let status: DaylightStatus
    private var previewProgress: Double?
    private var previewDate: Date?
    private var showsTimeLabels: Bool
    private var arcHeight: CGFloat
    private var daylightLayout: SolarArcDaylightLayout
    private let cloudArcRadiusScale: CGFloat = 0.82
    private let proportionalDayCloudArcRadiusScale: CGFloat = 0.72
    private let nightCloudArcRadiusScale: CGFloat = 0.72

    public init(
        status: DaylightStatus,
        previewProgress: Double? = nil,
        previewDate: Date? = nil,
        showsTimeLabels: Bool = true,
        arcHeight: CGFloat = 116,
        daylightLayout: SolarArcDaylightLayout = .normalized
    ) {
        self.status = status
        self.previewProgress = previewProgress
        self.previewDate = previewDate
        self.showsTimeLabels = showsTimeLabels
        self.arcHeight = arcHeight
        self.daylightLayout = daylightLayout
    }

    public var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let geometry = SolarArcGeometry(size: size, verticalOffset: 14)

                if daylightLayout == .proportional {
                    drawProportionalDaylightArc(in: context, size: size)
                    return
                }

                if displayProgress == nil {
                    drawNightDisk(in: context, size: size)
                    return
                }

                drawSunlightBackground(in: context, geometry: geometry)
                drawHorizon(in: context, size: size)
                drawCloudCoverArc(in: context, geometry: geometry)
                drawFutureArc(in: context, geometry: geometry)
                drawCompletedArc(in: context, geometry: geometry)
                drawSun(in: context, geometry: geometry)
            }
            .frame(height: arcHeight)

            if showsTimeLabels {
                HStack {
                    Text(timeText(displaySunrise))
                    Spacer()
                    Text(timeText(displaySolarNoon))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timeText(displaySunset))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Solar arc from \(timeText(displaySunrise)) to \(timeText(displaySunset))")
    }

    private func drawHorizon(in context: GraphicsContext, size: CGSize) {
        var horizon = Path()
        horizon.move(to: CGPoint(x: 8, y: size.height - 14))
        horizon.addLine(to: CGPoint(x: size.width - 8, y: size.height - 14))
        context.stroke(horizon, with: .color(.secondary.opacity(0.28)), lineWidth: 1)
    }

    private func drawFutureArc(in context: GraphicsContext, geometry: SolarArcGeometry) {
        var path = Path()
        path.addLines(geometry.points(from: 0, through: 1, steps: 72))
        context.stroke(path, with: .color(.secondary.opacity(0.22)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    private func drawCompletedArc(in context: GraphicsContext, geometry: SolarArcGeometry) {
        guard let progress = displayProgress else {
            return
        }

        var path = Path()
        path.addLines(geometry.points(from: 0, through: progress, steps: 48))
        context.stroke(path, with: .linearGradient(
            Gradient(colors: [.orange, .yellow]),
            startPoint: geometry.point(at: 0),
            endPoint: geometry.point(at: max(progress, 0.01))
        ), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
    }

    private func drawSunlightBackground(in context: GraphicsContext, geometry: SolarArcGeometry) {
        let points = status.arcPoints.sorted { $0.progress < $1.progress }
        let center = arcCenter(for: geometry)
        let radius = distance(from: center, to: geometry.point(at: 0.5))
        let fullFan = sunlightFanPath(from: 0, through: 1, center: center, geometry: geometry)

        if let rendered = SunlightFieldRenderer.render(
            geometry: SunlightFieldRenderer.Geometry(
                size: geometry.size,
                center: center,
                radius: radius,
                startAngle: -.pi,
                endAngle: 0,
                cloudRadiusScale: cloudArcRadiusScale,
                cutsGroundBelowBoundaryLines: false
            ),
            arcPoints: points,
            fallbackBrightness: status.brightness.score,
            fallbackCloudCover: status.brightness.cloudCover,
            displayScale: displayScale
        ) {
            var clippedContext = context
            clippedContext.clip(to: fullFan)
            clippedContext.draw(
                Image(decorative: rendered.cgImage, scale: rendered.scale, orientation: .up),
                in: CGRect(origin: .zero, size: geometry.size)
            )
            return
        }

        context.fill(
            fullFan,
            with: .radialGradient(
                Gradient(colors: [
                    clearSunlightColor(opacity: 0.32),
                    clearSunlightColor(opacity: 0.54)
                ]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private func drawCloudCoverArc(in context: GraphicsContext, geometry: SolarArcGeometry) {
        let points = status.arcPoints.sorted { $0.progress < $1.progress }
        guard points.count > 1 else {
            return
        }

        let samples = cloudArcSamples(
            from: points,
            steps: CloudTransitionSmoothing.lineSampleCount,
            smoothingRadius: CloudTransitionSmoothing.lineSmoothingRadius
        )
        guard samples.contains(where: { cloudFeatherOpacity(for: $0.cloudCover) > 0 }) else {
            return
        }

        for pair in zip(samples, samples.dropFirst()) {
            var segment = Path()
            segment.move(to: cloudPoint(at: pair.0.progress, geometry: geometry))
            segment.addLine(to: cloudPoint(at: pair.1.progress, geometry: geometry))
            let cloudCover = (pair.0.cloudCover + pair.1.cloudCover) / 2
            let featherOpacity = cloudFeatherOpacity(for: cloudCover)
            let opacity = cloudLineOpacity(for: cloudCover)
            guard featherOpacity > 0 else {
                continue
            }

            context.stroke(
                segment,
                with: .color(cloudFeatherLineColor(for: cloudCover)),
                style: StrokeStyle(lineWidth: 11.5, lineCap: .butt, lineJoin: .round)
            )

            guard opacity > 0 else {
                continue
            }

            context.stroke(
                segment,
                with: .color(cloudShadowLineColor(for: cloudCover)),
                style: StrokeStyle(lineWidth: 8.0, lineCap: .butt, lineJoin: .round)
            )

            context.stroke(
                segment,
                with: .color(cloudColor(for: cloudCover)),
                style: StrokeStyle(lineWidth: cloudBodyLineWidth(for: cloudCover, base: 5.0), lineCap: .butt, lineJoin: .round)
            )

            var highlight = Path()
            highlight.move(to: cloudPoint(at: pair.0.progress, geometry: geometry, radiusScale: 0.78))
            highlight.addLine(to: cloudPoint(at: pair.1.progress, geometry: geometry, radiusScale: 0.78))
            context.stroke(
                highlight,
                with: .color(.white.opacity(0.10 * opacity)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .butt, lineJoin: .round)
            )
        }
    }

    private func drawSun(in context: GraphicsContext, geometry: SolarArcGeometry) {
        guard let progress = displayProgress else {
            return
        }

        let sunPoint = geometry.point(at: progress)
        context.fill(
            Path(ellipseIn: CGRect(x: sunPoint.x - 10, y: sunPoint.y - 10, width: 20, height: 20)),
            with: .color(.yellow)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: sunPoint.x - 10, y: sunPoint.y - 10, width: 20, height: 20)),
            with: .color(.orange),
            lineWidth: 2
        )
    }

    private func drawProportionalDaylightArc(in context: GraphicsContext, size: CGSize) {
        let geometry = ProportionalDaylightArcGeometry(
            size: size,
            dayFraction: daylightFraction(sunrise: displaySunrise, sunset: displaySunset)
        )

        drawProportionalSunlightBackground(in: context, geometry: geometry)
        drawProportionalCloudCoverArc(in: context, geometry: geometry)
        drawProportionalFutureArc(in: context, geometry: geometry)
        drawProportionalCompletedArc(in: context, geometry: geometry)
        clearProportionalGroundRegion(in: context, geometry: geometry)
        drawProportionalBoundaryLines(in: context, geometry: geometry)
        drawProportionalNightSun(in: context, geometry: geometry)
        drawProportionalSun(in: context, geometry: geometry)
    }

    private func drawProportionalFutureArc(in context: GraphicsContext, geometry: ProportionalDaylightArcGeometry) {
        var clippedContext = context
        clippedContext.clip(to: proportionalSunlightFanPath(from: 0, through: 1, geometry: geometry))

        var path = Path()
        path.addLines(geometry.points(from: 0, through: 1, steps: 96))
        clippedContext.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    .white.opacity(0.18),
                    clearSunlightColor(opacity: 0.42),
                    .white.opacity(0.14)
                ]),
                startPoint: geometry.point(at: 0),
                endPoint: geometry.point(at: 1)
            ),
            style: StrokeStyle(lineWidth: 4.6, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawProportionalCompletedArc(in context: GraphicsContext, geometry: ProportionalDaylightArcGeometry) {
        guard let progress = displayProgress else {
            return
        }

        var clippedContext = context
        clippedContext.clip(to: proportionalSunlightFanPath(from: 0, through: 1, geometry: geometry))

        var path = Path()
        path.addLines(geometry.points(from: 0, through: progress, steps: 64))
        clippedContext.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    warmSunlightColor(opacity: 0.96),
                    clearSunlightColor(opacity: 1),
                    .white.opacity(0.88)
                ]),
                startPoint: geometry.point(at: 0),
                endPoint: geometry.point(at: max(progress, 0.01))
            ),
            style: StrokeStyle(lineWidth: 5.8, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawProportionalSunlightBackground(
        in context: GraphicsContext,
        geometry: ProportionalDaylightArcGeometry
    ) {
        let points = status.arcPoints.sorted { $0.progress < $1.progress }
        guard points.count > 1 else {
            return
        }

        let center = geometry.center
        let radius = geometry.radius
        let fullFan = proportionalSunlightFanPath(from: 0, through: 1, geometry: geometry)

        context.fill(fullFan, with: .color(Color.white.opacity(0.035)))

        let currentBrightness = brightnessScoreValue(status.brightness.score)
        if let rendered = SunlightFieldRenderer.render(
            geometry: SunlightFieldRenderer.Geometry(
                size: geometry.size,
                center: center,
                radius: radius,
                startAngle: geometry.sunriseAngle,
                endAngle: geometry.sunsetAngle,
                cloudRadiusScale: proportionalDayCloudArcRadiusScale,
                cutsGroundBelowBoundaryLines: true
            ),
            arcPoints: points,
            fallbackBrightness: status.brightness.score,
            fallbackCloudCover: status.brightness.cloudCover,
            displayScale: displayScale
        ) {
            var clippedContext = context
            clippedContext.clip(to: fullFan)
            clippedContext.draw(
                Image(decorative: rendered.cgImage, scale: rendered.scale, orientation: .up),
                in: CGRect(origin: .zero, size: geometry.size)
            )
        } else {
            context.fill(
                fullFan,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: clearSunlightColor(opacity: 0.26 + (currentBrightness * 0.16)), location: 0),
                        .init(color: clearSunlightColor(opacity: 0.42 + (currentBrightness * 0.18)), location: 0.70),
                        .init(color: warmSunlightColor(opacity: 0.44 + (currentBrightness * 0.22)), location: 1)
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }

        drawProportionalGlassSheen(in: context, geometry: geometry, fullFan: fullFan)
    }

    private func drawProportionalBoundaryLines(in context: GraphicsContext, geometry: ProportionalDaylightArcGeometry) {
        drawGlassRadialLine(
            in: context,
            center: geometry.center,
            radius: geometry.radius,
            angle: geometry.sunriseAngle,
            color: warmSunlightColor(opacity: 0.66)
        )
        drawGlassRadialLine(
            in: context,
            center: geometry.center,
            radius: geometry.radius,
            angle: geometry.sunsetAngle,
            color: warmSunlightColor(opacity: 0.66)
        )
    }

    private func clearProportionalGroundRegion(in context: GraphicsContext, geometry: ProportionalDaylightArcGeometry) {
        var cutoutContext = context
        cutoutContext.blendMode = .destinationOut
        cutoutContext.fill(
            proportionalGroundCutoutPath(geometry: geometry),
            with: .color(.white)
        )
    }

    private func drawProportionalCloudCoverArc(
        in context: GraphicsContext,
        geometry: ProportionalDaylightArcGeometry
    ) {
        let points = status.arcPoints.sorted { $0.progress < $1.progress }
        guard points.count > 1 else {
            return
        }

        let samples = cloudArcSamples(
            from: points,
            steps: CloudTransitionSmoothing.compactLineSampleCount,
            smoothingRadius: CloudTransitionSmoothing.compactLineSmoothingRadius
        )
        guard samples.contains(where: { cloudFeatherOpacity(for: $0.cloudCover) > 0 }) else {
            return
        }

        var clippedContext = context
        clippedContext.clip(to: proportionalSunlightFanPath(from: 0, through: 1, geometry: geometry))

        drawCloudBandLayer(
            in: &clippedContext,
            geometry: geometry,
            samples: samples,
            threshold: 0.05,
            radiusScale: proportionalDayCloudArcRadiusScale,
            lineWidth: 13.0,
            color: Color(white: 0.72).opacity(0.14)
        )
        drawCloudBandLayer(
            in: &clippedContext,
            geometry: geometry,
            samples: samples,
            threshold: 0.18,
            radiusScale: proportionalDayCloudArcRadiusScale,
            lineWidth: 9.0,
            color: Color(red: 0.04, green: 0.04, blue: 0.045).opacity(0.34)
        )
        drawCloudBandLayer(
            in: &clippedContext,
            geometry: geometry,
            samples: samples,
            threshold: 0.36,
            radiusScale: proportionalDayCloudArcRadiusScale,
            lineWidth: 7.0,
            color: Color(white: 0.46).opacity(0.58)
        )
        drawCloudBandLayer(
            in: &clippedContext,
            geometry: geometry,
            samples: samples,
            threshold: 0.72,
            radiusScale: proportionalDayCloudArcRadiusScale,
            lineWidth: 6.4,
            color: Color(white: 0.24).opacity(0.48)
        )
        drawCloudBandLayer(
            in: &clippedContext,
            geometry: geometry,
            samples: samples,
            threshold: 0.16,
            radiusScale: proportionalDayCloudArcRadiusScale - 0.035,
            lineWidth: 1.3,
            color: .white.opacity(0.13)
        )
    }

    private func drawProportionalSun(in context: GraphicsContext, geometry: ProportionalDaylightArcGeometry) {
        guard let progress = displayProgress else {
            return
        }

        let sunPoint = geometry.point(at: progress)
        let rect = CGRect(x: sunPoint.x - 10, y: sunPoint.y - 10, width: 20, height: 20)
        context.fill(
            Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
            with: .radialGradient(
                Gradient(colors: [
                    clearSunlightColor(opacity: 0.46),
                    clearSunlightColor(opacity: 0)
                ]),
                center: sunPoint,
                startRadius: 0,
                endRadius: 18
            )
        )
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    .white.opacity(0.96),
                    clearSunlightColor(opacity: 1),
                    warmSunlightColor(opacity: 0.96)
                ]),
                center: CGPoint(x: sunPoint.x - 4, y: sunPoint.y - 5),
                startRadius: 0,
                endRadius: 13
            )
        )
        context.stroke(Path(ellipseIn: rect), with: .color(warmSunlightColor(opacity: 0.88)), lineWidth: 2.4)
    }

    private func drawProportionalNightSun(in context: GraphicsContext, geometry: ProportionalDaylightArcGeometry) {
        guard displayProgress == nil,
              let nightAngle = nightSunAngle(
                date: displayDate,
                sunrise: displaySunrise,
                sunset: displaySunset,
                sunriseAngle: geometry.sunriseAngle,
                sunsetAngle: geometry.sunsetAngle
              ) else {
            return
        }

        let sunPoint = point(center: geometry.center, radius: geometry.radius * 0.78, angle: nightAngle)
        let radius = max(min(geometry.radius * 0.12, 7), 4.5)
        let rect = CGRect(x: sunPoint.x - radius, y: sunPoint.y - radius, width: radius * 2, height: radius * 2)

        context.fill(
            Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
            with: .radialGradient(
                Gradient(colors: [
                    warmSunlightColor(opacity: 0.22),
                    warmSunlightColor(opacity: 0)
                ]),
                center: sunPoint,
                startRadius: 0,
                endRadius: radius + 8
            )
        )
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    clearSunlightColor(opacity: 0.56),
                    warmSunlightColor(opacity: 0.50),
                    Color(red: 0.72, green: 0.40, blue: 0.12).opacity(0.44)
                ]),
                center: CGPoint(x: sunPoint.x - radius * 0.35, y: sunPoint.y - radius * 0.40),
                startRadius: 0,
                endRadius: radius
            )
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(warmSunlightColor(opacity: 0.48)),
            lineWidth: 1.6
        )
    }

    private func drawNightDisk(in context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width * 0.36, size.height * 0.48)
        let samples = status.arcPoints.sorted { $0.progress < $1.progress }
        let sunrise = samples.first?.date ?? status.solar.sunrise
        let sunset = samples.last?.date ?? status.solar.sunset
        let dayFraction = daylightFraction(sunrise: sunrise, sunset: sunset)
        let dayAngle = CGFloat(dayFraction * 2 * .pi)
        let sunriseAngle = CGFloat(-Double.pi / 2) - (dayAngle / 2)
        let sunsetAngle = sunriseAngle + dayAngle

        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.secondary.opacity(0.16))
        )

        drawNightSunlightBackground(
            in: context,
            center: center,
            radius: radius,
            sunriseAngle: sunriseAngle,
            dayAngle: dayAngle,
            samples: samples,
            fallbackStartAngle: sunriseAngle,
            fallbackEndAngle: sunsetAngle
        )

        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.secondary.opacity(0.34)),
            lineWidth: 1
        )

        drawRadialLine(in: context, center: center, radius: radius, angle: sunriseAngle, color: .orange.opacity(0.58))
        drawRadialLine(in: context, center: center, radius: radius, angle: sunsetAngle, color: .orange.opacity(0.58))
        drawNightCloudCoverArc(in: context, center: center, radius: radius * 0.72, sunriseAngle: sunriseAngle, dayAngle: dayAngle, samples: samples)

        if let previewProgress {
            let angle = sunriseAngle + CGFloat(min(max(previewProgress, 0), 1)) * dayAngle
            drawDiskSun(in: context, at: point(center: center, radius: radius * 0.86, angle: angle), radius: 8, opacity: 1)
        }

        if let nightAngle = nightSunAngle(
            date: displayDate,
            sunrise: sunrise,
            sunset: sunset,
            sunriseAngle: sunriseAngle,
            sunsetAngle: sunsetAngle
        ) {
            drawDiskSun(in: context, at: point(center: center, radius: radius * 0.78, angle: nightAngle), radius: 6, opacity: 0.48)
        }
    }

    private func drawNightSunlightBackground(
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        sunriseAngle: CGFloat,
        dayAngle: CGFloat,
        samples: [SunArcPoint],
        fallbackStartAngle: CGFloat,
        fallbackEndAngle: CGFloat
    ) {
        guard samples.count > 1 else {
            context.fill(
                wedgePath(center: center, radius: radius, startAngle: fallbackStartAngle, endAngle: fallbackEndAngle),
                with: .linearGradient(
                    Gradient(colors: [
                        warmSunlightColor(opacity: 0.34),
                        clearSunlightColor(opacity: 0.46)
                    ]),
                    startPoint: point(center: center, radius: radius, angle: fallbackStartAngle),
                    endPoint: point(center: center, radius: radius, angle: fallbackEndAngle)
                )
            )
            return
        }

        for pair in zip(samples, samples.dropFirst()) {
            let startAngle = sunriseAngle + CGFloat(pair.0.progress) * dayAngle
            let endAngle = sunriseAngle + CGFloat(pair.1.progress) * dayAngle
            let startPoint = point(center: center, radius: radius, angle: startAngle)
            let endPoint = point(center: center, radius: radius, angle: endAngle)
            let segment = wedgePath(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle)

            context.fill(
                segment,
                with: .linearGradient(
                    Gradient(colors: [
                        warmSunlightColor(opacity: 0.28),
                        clearSunlightColor(opacity: 0.36)
                    ]),
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )

            context.fill(
                segment,
                with: .radialGradient(
                    Gradient(colors: [
                        clearSunlightColor(opacity: 0.22),
                        clearSunlightColor(opacity: 0.44)
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }

        let cloudSamples = cloudArcSamples(
            from: samples,
            steps: CloudTransitionSmoothing.nightShadeSampleCount,
            smoothingRadius: CloudTransitionSmoothing.nightShadeSmoothingRadius
        )
        for pair in zip(cloudSamples, cloudSamples.dropFirst()) {
            let startAngle = sunriseAngle + CGFloat(pair.0.progress) * dayAngle
            let endAngle = sunriseAngle + CGFloat(pair.1.progress) * dayAngle
            let cloudCover = (pair.0.cloudCover + pair.1.cloudCover) / 2
            guard cloudOcclusionIntensity(for: cloudCover) > 0 else {
                continue
            }

            drawCloudOcclusion(
                in: context,
                segment: wedgePath(
                    center: center,
                    radius: radius * nightCloudArcRadiusScale,
                    startAngle: startAngle,
                    endAngle: endAngle
                ),
                center: center,
                radius: radius * nightCloudArcRadiusScale,
                cloudCover: cloudCover
            )
        }
    }

    private func drawNightCloudCoverArc(
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        sunriseAngle: CGFloat,
        dayAngle: CGFloat,
        samples: [SunArcPoint]
    ) {
        guard samples.count > 1 else {
            return
        }

        let cloudSamples = cloudArcSamples(
            from: samples,
            steps: CloudTransitionSmoothing.lineSampleCount,
            smoothingRadius: CloudTransitionSmoothing.lineSmoothingRadius
        )
        guard cloudSamples.contains(where: { cloudFeatherOpacity(for: $0.cloudCover) > 0 }) else {
            return
        }

        for pair in zip(cloudSamples, cloudSamples.dropFirst()) {
            let startAngle = sunriseAngle + CGFloat(pair.0.progress) * dayAngle
            let endAngle = sunriseAngle + CGFloat(pair.1.progress) * dayAngle
            let cloudCover = (pair.0.cloudCover + pair.1.cloudCover) / 2
            let featherOpacity = cloudFeatherOpacity(for: cloudCover)
            let opacity = cloudLineOpacity(for: cloudCover)
            guard featherOpacity > 0 else {
                continue
            }

            context.stroke(
                arcPath(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle),
                with: .color(cloudFeatherLineColor(for: cloudCover)),
                style: StrokeStyle(lineWidth: 9.4, lineCap: .butt, lineJoin: .round)
            )

            guard opacity > 0 else {
                continue
            }

            context.stroke(
                arcPath(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle),
                with: .color(cloudShadowLineColor(for: cloudCover)),
                style: StrokeStyle(lineWidth: 7.2, lineCap: .butt, lineJoin: .round)
            )

            context.stroke(
                arcPath(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle),
                with: .color(cloudColor(for: cloudCover)),
                style: StrokeStyle(lineWidth: cloudBodyLineWidth(for: cloudCover, base: 4.8), lineCap: .butt, lineJoin: .round)
            )

            context.stroke(
                arcPath(center: center, radius: max(radius - 2, 0), startAngle: startAngle, endAngle: endAngle),
                with: .color(.white.opacity(0.08 * opacity)),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .butt, lineJoin: .round)
            )
        }
    }

    private func drawRadialLine(in context: GraphicsContext, center: CGPoint, radius: CGFloat, angle: CGFloat, color: Color) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center: center, radius: radius, angle: angle))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    private func drawGlassRadialLine(
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        angle: CGFloat,
        color: Color
    ) {
        var line = Path()
        line.move(to: center)
        line.addLine(to: point(center: center, radius: radius, angle: angle))

        context.stroke(
            line,
            with: .color(.white.opacity(0.18)),
            style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
        )
        context.stroke(
            line,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
        )
    }

    private func drawDiskSun(in context: GraphicsContext, at point: CGPoint, radius: CGFloat, opacity: Double) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(.yellow.opacity(opacity)))
        context.stroke(Path(ellipseIn: rect), with: .color(.orange.opacity(opacity)), lineWidth: 2)
    }

    private func wedgePath(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) -> Path {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center: center, radius: radius, angle: startAngle))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: Angle(radians: Double(startAngle)),
            endAngle: Angle(radians: Double(endAngle)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }

    private func arcPath(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: Angle(radians: Double(startAngle)),
            endAngle: Angle(radians: Double(endAngle)),
            clockwise: false
        )
        return path
    }

    private func annularWedgePath(
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat
    ) -> Path {
        let clampedInnerRadius = min(max(innerRadius, 0), outerRadius)
        var path = Path()
        path.move(to: point(center: center, radius: clampedInnerRadius, angle: startAngle))
        path.addLine(to: point(center: center, radius: outerRadius, angle: startAngle))
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: Angle(radians: Double(startAngle)),
            endAngle: Angle(radians: Double(endAngle)),
            clockwise: false
        )
        path.addLine(to: point(center: center, radius: clampedInnerRadius, angle: endAngle))
        path.addArc(
            center: center,
            radius: clampedInnerRadius,
            startAngle: Angle(radians: Double(endAngle)),
            endAngle: Angle(radians: Double(startAngle)),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func proportionalGroundCutoutPath(geometry: ProportionalDaylightArcGeometry) -> Path {
        let left = geometry.point(at: 0)
        let center = geometry.center
        let right = geometry.point(at: 1)
        let overscan = max(geometry.size.width, geometry.size.height)

        var path = Path()
        path.move(to: left)
        path.addLine(to: center)
        path.addLine(to: right)
        path.addLine(to: CGPoint(x: geometry.size.width + overscan, y: geometry.size.height + overscan))
        path.addLine(to: CGPoint(x: -overscan, y: geometry.size.height + overscan))
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func daylightFraction(sunrise: Date?, sunset: Date?) -> Double {
        guard let sunrise, let sunset, sunset > sunrise else {
            return 0.5
        }

        return min(max(sunset.timeIntervalSince(sunrise) / 86_400, 0.02), 0.98)
    }

    private func nightSunAngle(
        date: Date,
        sunrise: Date?,
        sunset: Date?,
        sunriseAngle: CGFloat,
        sunsetAngle: CGFloat
    ) -> CGFloat? {
        guard let sunrise, let sunset, sunset > sunrise else {
            return .pi / 2
        }

        if date < sunrise {
            let previousSunset = sunset.addingTimeInterval(-86_400)
            let span = sunrise.timeIntervalSince(previousSunset)
            guard span > 0 else {
                return .pi / 2
            }

            let ratio = min(max(date.timeIntervalSince(previousSunset) / span, 0), 1)
            return sunsetAngle + CGFloat(ratio) * ((sunriseAngle + (2 * .pi)) - sunsetAngle)
        }

        let nextSunrise = sunrise.addingTimeInterval(86_400)
        let span = nextSunrise.timeIntervalSince(sunset)
        guard span > 0 else {
            return .pi / 2
        }

        let ratio = min(max(date.timeIntervalSince(sunset) / span, 0), 1)
        return sunsetAngle + CGFloat(ratio) * ((sunriseAngle + (2 * .pi)) - sunsetAngle)
    }

    private var displayProgress: Double? {
        if previewDate != nil {
            return previewProgress
        }

        return previewProgress ?? status.solar.daylightProgress
    }

    private var displayDate: Date {
        previewDate ?? status.solar.date
    }

    private var sortedArcPoints: [SunArcPoint] {
        status.arcPoints.sorted { $0.progress < $1.progress }
    }

    private var displaySunrise: Date? {
        sortedArcPoints.first?.date ?? status.solar.sunrise
    }

    private var displaySolarNoon: Date? {
        sortedArcPoints.min {
            abs($0.progress - 0.5) < abs($1.progress - 0.5)
        }?.date ?? status.solar.solarNoon
    }

    private var displaySunset: Date? {
        sortedArcPoints.last?.date ?? status.solar.sunset
    }

    private func arcCenter(for geometry: SolarArcGeometry) -> CGPoint {
        CGPoint(x: geometry.size.width / 2, y: geometry.size.height - geometry.verticalOffset)
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func sunlightFanPath(from start: Double, through end: Double, center: CGPoint, geometry: SolarArcGeometry) -> Path {
        let clampedStart = min(max(start, 0), 1)
        let clampedEnd = min(max(end, 0), 1)
        let steps = max(Int((abs(clampedEnd - clampedStart) * 72).rounded(.up)), 2)
        let points = (0...steps).map { index in
            let progress = clampedStart + ((clampedEnd - clampedStart) * Double(index) / Double(steps))
            return geometry.point(at: progress)
        }

        var path = Path()
        path.move(to: center)
        path.addLine(to: geometry.point(at: clampedStart))
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    private func cloudBlockedFanPath(
        from start: Double,
        through end: Double,
        center: CGPoint,
        geometry: SolarArcGeometry,
        radiusScale: CGFloat
    ) -> Path {
        let clampedStart = min(max(start, 0), 1)
        let clampedEnd = min(max(end, 0), 1)
        let steps = max(Int((abs(clampedEnd - clampedStart) * 96).rounded(.up)), 2)
        let points = (0...steps).map { index in
            let progress = clampedStart + ((clampedEnd - clampedStart) * Double(index) / Double(steps))
            return geometry.point(at: progress, radiusScale: radiusScale)
        }

        var path = Path()
        path.move(to: center)
        path.addLine(to: geometry.point(at: clampedStart, radiusScale: radiusScale))
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    private func proportionalSunlightFanPath(
        from start: Double,
        through end: Double,
        geometry: ProportionalDaylightArcGeometry
    ) -> Path {
        let clampedStart = min(max(start, 0), 1)
        let clampedEnd = min(max(end, 0), 1)
        let steps = max(Int((abs(clampedEnd - clampedStart) * 96).rounded(.up)), 2)
        let points = (0...steps).map { index in
            let progress = clampedStart + ((clampedEnd - clampedStart) * Double(index) / Double(steps))
            return geometry.point(at: progress)
        }

        var path = Path()
        path.move(to: geometry.center)
        path.addLine(to: geometry.point(at: clampedStart))
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    private func drawCloudOcclusion(
        in context: GraphicsContext,
        segment: Path,
        center: CGPoint,
        radius: CGFloat,
        cloudCover: Double
    ) {
        let intensity = cloudOcclusionIntensity(for: cloudCover)
        guard intensity > 0 else {
            return
        }

        let coreOpacity = 0.52 + (intensity * 0.44)
        let midOpacity = 0.50 + (intensity * 0.40)
        let boundaryOpacity = 0.62 + (intensity * 0.34)
        let shadowOpacity = 0.22 + (intensity * 0.58)

        context.fill(
            segment,
            with: .color(Color(red: 0.028, green: 0.032, blue: 0.032).opacity(shadowOpacity))
        )

        context.fill(
            segment,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.018, green: 0.026, blue: 0.028).opacity(coreOpacity), location: 0),
                    .init(color: Color(red: 0.030, green: 0.034, blue: 0.030).opacity(coreOpacity), location: 0.54),
                    .init(color: Color(red: 0.060, green: 0.054, blue: 0.040).opacity(midOpacity), location: 0.82),
                    .init(color: Color(red: 0.090, green: 0.070, blue: 0.040).opacity(boundaryOpacity), location: 0.96),
                    .init(color: Color(red: 0.030, green: 0.034, blue: 0.033).opacity(boundaryOpacity), location: 1)
                ]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private func drawProportionalCloudShadowBands(
        in context: GraphicsContext,
        geometry: ProportionalDaylightArcGeometry,
        samples: [CloudArcSample],
        points: [SunArcPoint]
    ) {
        drawCloudShadowLayer(in: context, geometry: geometry, samples: samples, threshold: 0.18, opacity: 0.22)
        drawCloudShadowLayer(in: context, geometry: geometry, samples: samples, threshold: 0.42, opacity: 0.20)
        drawCloudShadowLayer(in: context, geometry: geometry, samples: samples, threshold: 0.68, opacity: 0.18)
        drawCloudShadowLayer(in: context, geometry: geometry, samples: samples, threshold: 0.86, opacity: 0.12)
        drawCloudTopLightLayer(in: context, geometry: geometry, samples: samples, points: points, threshold: 0.18)
        drawCloudTopLightLayer(in: context, geometry: geometry, samples: samples, points: points, threshold: 0.56)
    }

    private func drawCloudShadowLayer(
        in context: GraphicsContext,
        geometry: ProportionalDaylightArcGeometry,
        samples: [CloudArcSample],
        threshold: Double,
        opacity: Double
    ) {
        for range in cloudArcRanges(from: samples, threshold: threshold) {
            context.fill(
                wedgePath(
                    center: geometry.center,
                    radius: geometry.radius * proportionalDayCloudArcRadiusScale,
                    startAngle: geometry.angle(at: range.start),
                    endAngle: geometry.angle(at: range.end)
                ),
                with: .color(Color(red: 0.014, green: 0.017, blue: 0.022).opacity(opacity))
            )
        }
    }

    private func drawCloudTopLightLayer(
        in context: GraphicsContext,
        geometry: ProportionalDaylightArcGeometry,
        samples: [CloudArcSample],
        points: [SunArcPoint],
        threshold: Double
    ) {
        let brightnessCurve = SmoothProgressCurve(
            points: points,
            fallback: brightnessScoreValue(status.brightness.score),
            value: \.brightnessScore
        )

        for range in cloudArcRanges(from: samples, threshold: threshold) {
            let midProgress = (range.start + range.end) / 2
            let brightness = brightnessCurve.value(at: midProgress)
            let brightnessLift = min(max(brightness, 0), 1)
            let segment = annularWedgePath(
                center: geometry.center,
                innerRadius: geometry.radius * proportionalDayCloudArcRadiusScale,
                outerRadius: geometry.radius,
                startAngle: geometry.angle(at: range.start),
                endAngle: geometry.angle(at: range.end)
            )

            context.fill(
                segment,
                with: .color(clearSunlightColor(opacity: 0.08 + (brightnessLift * 0.06)))
            )
            context.fill(
                segment,
                with: .color(warmSunlightColor(opacity: 0.08 + (threshold * 0.08)))
            )
        }
    }

    private func drawProportionalGlassSheen(
        in context: GraphicsContext,
        geometry: ProportionalDaylightArcGeometry,
        fullFan: Path
    ) {
        var clippedContext = context
        clippedContext.clip(to: fullFan)

        clippedContext.fill(
            fullFan,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.18), location: 0),
                    .init(color: .white.opacity(0.05), location: 0.46),
                    .init(color: .white.opacity(0.00), location: 0.72),
                    .init(color: .white.opacity(0.08), location: 1)
                ]),
                startPoint: CGPoint(x: geometry.center.x - geometry.radius, y: geometry.center.y - geometry.radius),
                endPoint: CGPoint(x: geometry.center.x + geometry.radius, y: geometry.center.y + geometry.radius)
            )
        )

        clippedContext.stroke(
            arcPath(
                center: geometry.center,
                radius: geometry.radius,
                startAngle: geometry.sunriseAngle,
                endAngle: geometry.sunsetAngle
            ),
            with: .linearGradient(
                Gradient(colors: [
                    warmSunlightColor(opacity: 0.90),
                    clearSunlightColor(opacity: 0.88),
                    .white.opacity(0.45)
                ]),
                startPoint: geometry.point(at: 0),
                endPoint: geometry.point(at: 1)
            ),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawCloudBandLayer(
        in context: inout GraphicsContext,
        geometry: ProportionalDaylightArcGeometry,
        samples: [CloudArcSample],
        threshold: Double,
        radiusScale: CGFloat,
        lineWidth: CGFloat,
        color: Color
    ) {
        for range in cloudArcRanges(from: samples, threshold: threshold) {
            context.stroke(
                arcPath(
                    center: geometry.center,
                    radius: geometry.radius * radiusScale,
                    startAngle: geometry.angle(at: range.start),
                    endAngle: geometry.angle(at: range.end)
                ),
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func cloudPoint(at progress: Double, geometry: SolarArcGeometry) -> CGPoint {
        cloudPoint(at: progress, geometry: geometry, radiusScale: cloudArcRadiusScale)
    }

    private func cloudPoint(at progress: Double, geometry: SolarArcGeometry, radiusScale: CGFloat) -> CGPoint {
        geometry.point(at: progress, radiusScale: radiusScale)
    }

    private struct CloudArcSample {
        let progress: Double
        let cloudCover: Double
    }

    private struct CloudArcRange {
        let start: Double
        let end: Double
    }

    private func cloudArcRanges(from samples: [CloudArcSample], threshold: Double) -> [CloudArcRange] {
        guard samples.count > 1 else {
            return []
        }

        let clampedThreshold = min(max(threshold, 0), 1)
        var ranges: [CloudArcRange] = []
        var activeStart: Double?

        for pair in zip(samples, samples.dropFirst()) {
            let startValue = pair.0.cloudCover
            let endValue = pair.1.cloudCover

            if activeStart == nil {
                if startValue > clampedThreshold {
                    activeStart = pair.0.progress
                } else if endValue > clampedThreshold {
                    activeStart = cloudThresholdCrossing(
                        threshold: clampedThreshold,
                        lower: pair.0,
                        upper: pair.1
                    )
                }
            }

            guard let rangeStart = activeStart else {
                continue
            }

            if endValue <= clampedThreshold {
                let rangeEnd = cloudThresholdCrossing(
                    threshold: clampedThreshold,
                    lower: pair.0,
                    upper: pair.1
                )

                if rangeEnd > rangeStart {
                    ranges.append(CloudArcRange(start: rangeStart, end: rangeEnd))
                }
                activeStart = nil
            }
        }

        if let rangeStart = activeStart,
           let lastProgress = samples.last?.progress,
           lastProgress > rangeStart {
            ranges.append(CloudArcRange(start: rangeStart, end: lastProgress))
        }

        return ranges
    }

    private func cloudThresholdCrossing(
        threshold: Double,
        lower: CloudArcSample,
        upper: CloudArcSample
    ) -> Double {
        let span = upper.cloudCover - lower.cloudCover
        guard span != 0 else {
            return upper.progress
        }

        let ratio = min(max((threshold - lower.cloudCover) / span, 0), 1)
        return lower.progress + ((upper.progress - lower.progress) * ratio)
    }

    private func cloudArcSamples(from points: [SunArcPoint], steps: Int, smoothingRadius: Int = 0) -> [CloudArcSample] {
        let sortedPoints = points.sorted { $0.progress < $1.progress }
        let totalSteps = max(steps, 2)
        // Uses the same monotone cubic curve as the shaded sunlight field.
        let cloudCurve = SmoothProgressCurve(
            points: sortedPoints,
            fallback: cloudCoverValue(nil),
            value: \.cloudCover
        )

        let samples = (0...totalSteps).map { index in
            let progress = Double(index) / Double(totalSteps)
            return CloudArcSample(
                progress: progress,
                cloudCover: cloudCurve.value(at: progress)
            )
        }

        return smoothCloudArcSamples(samples, radius: smoothingRadius)
    }

    private func smoothCloudArcSamples(_ samples: [CloudArcSample], radius: Int) -> [CloudArcSample] {
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

            return CloudArcSample(
                progress: samples[index].progress,
                cloudCover: weightedCloudCover / totalWeight
            )
        }
    }

    private func cloudCoverValue(_ value: Double?) -> Double {
        min(max(value ?? status.brightness.cloudCover ?? 0, 0), 1)
    }

    private func brightnessScoreValue(_ value: Double?) -> Double {
        min(max(value ?? status.brightness.score, 0), 1)
    }

    private func clearSunlightColor(opacity: Double) -> Color {
        Color(red: 1.00, green: 0.84, blue: 0.08, opacity: min(max(opacity, 0), 1))
    }

    private func warmSunlightColor(opacity: Double) -> Color {
        Color(red: 1.00, green: 0.54, blue: 0.06, opacity: min(max(opacity, 0), 1))
    }

    private func cloudFeatherOpacity(for cloudCover: Double) -> Double {
        smoothRamp(cloudCover, threshold: 0.04)
    }

    private func cloudLineOpacity(for cloudCover: Double) -> Double {
        smoothRamp(cloudCover, threshold: 0.06)
    }

    private func cloudOcclusionIntensity(for cloudCover: Double) -> Double {
        smoothRamp(cloudCover, threshold: 0.18)
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

    private func cloudFeatherLineColor(for cloudCover: Double) -> Color {
        let opacity = cloudFeatherOpacity(for: cloudCover)
        return Color(white: 0.70).opacity(0.16 * opacity)
    }

    private func cloudShadowLineColor(for cloudCover: Double) -> Color {
        let opacity = cloudLineOpacity(for: cloudCover)
        return Color(red: 0.04, green: 0.04, blue: 0.045).opacity(0.34 * opacity)
    }

    private func cloudBodyLineWidth(for cloudCover: Double, base: CGFloat) -> CGFloat {
        base + CGFloat(cloudOcclusionIntensity(for: cloudCover)) * 2.2
    }

    private func cloudColor(for cloudCover: Double) -> Color {
        let clamped = min(max(cloudCover, 0), 1)
        let visibility = cloudLineOpacity(for: clamped)
        let white = 0.92 - (clamped * 0.64)
        let opacity = 0.18 + (visibility * 0.74)
        return Color(white: white).opacity(opacity)
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.timeZone = status.timezone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ProportionalDaylightArcGeometry {
    let size: CGSize
    let dayFraction: Double

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

    func angle(at progress: Double) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return sunriseAngle + (CGFloat(clampedProgress) * dayAngle)
    }

    func point(at progress: Double, radiusScale: CGFloat = 1) -> CGPoint {
        let clampedRadiusScale = min(max(radiusScale, 0), 1)
        let angle = angle(at: progress)
        let scaledRadius = radius * clampedRadiusScale

        return CGPoint(
            x: center.x + cos(angle) * scaledRadius,
            y: center.y + sin(angle) * scaledRadius
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

#if DEBUG
private enum SolarArcViewPreviewData {
    static let cloudShiftStatus = SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus

    static var nightStatus: DaylightStatus {
        let timezone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let date = calendar.date(from: DateComponents(
            timeZone: timezone,
            year: 2026,
            month: 6,
            day: 21,
            hour: 22,
            minute: 15
        )) ?? Date(timeIntervalSince1970: 1_782_025_000)

        return MockDaylightProvider(timezone: timezone).status(at: date)
    }
}

#Preview("Solar Arc - Cloud Shift", traits: .sizeThatFitsLayout) {
    SolarArcView(
        status: SolarArcViewPreviewData.cloudShiftStatus,
        showsTimeLabels: true,
        arcHeight: 126,
        daylightLayout: .proportional
    )
    .frame(width: 320)
    .padding(20)
}

#Preview("Solar Arc - Night", traits: .sizeThatFitsLayout) {
    SolarArcView(
        status: SolarArcViewPreviewData.nightStatus,
        showsTimeLabels: true,
        arcHeight: 126
    )
    .frame(width: 320)
    .padding(20)
}
#endif
