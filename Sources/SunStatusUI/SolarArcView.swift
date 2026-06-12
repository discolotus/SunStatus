import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif

public struct SolarArcView: View {
    private let status: DaylightStatus
    private var previewProgress: Double?
    private var showsTimeLabels: Bool
    private var arcHeight: CGFloat

    public init(
        status: DaylightStatus,
        previewProgress: Double? = nil,
        showsTimeLabels: Bool = true,
        arcHeight: CGFloat = 116
    ) {
        self.status = status
        self.previewProgress = previewProgress
        self.showsTimeLabels = showsTimeLabels
        self.arcHeight = arcHeight
    }

    public var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let geometry = SolarArcGeometry(size: size, verticalOffset: 14)

                if status.solar.daylightProgress == nil {
                    drawNightDisk(in: context, size: size)
                    return
                }

                drawHorizon(in: context, size: size)
                drawCloudCoverArc(in: context, geometry: geometry)
                drawFutureArc(in: context, geometry: geometry)
                drawCompletedArc(in: context, geometry: geometry)
                drawSun(in: context, geometry: geometry)
            }
            .frame(height: arcHeight)

            if showsTimeLabels {
                HStack {
                    Text(timeText(status.solar.sunrise))
                    Spacer()
                    Text(timeText(status.solar.solarNoon))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timeText(status.solar.sunset))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Solar arc from \(timeText(status.solar.sunrise)) to \(timeText(status.solar.sunset))")
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

    private func drawCloudCoverArc(in context: GraphicsContext, geometry: SolarArcGeometry) {
        let points = status.arcPoints.sorted { $0.progress < $1.progress }
        guard points.count > 1 else {
            return
        }

        for pair in zip(points, points.dropFirst()) {
            var segment = Path()
            segment.move(to: cloudPoint(at: pair.0.progress, geometry: geometry))
            segment.addLine(to: cloudPoint(at: pair.1.progress, geometry: geometry))
            let cloudCover = averageCloudCover(pair.0.cloudCover, pair.1.cloudCover)

            context.stroke(
                segment,
                with: .color(cloudColor(for: cloudCover)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
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

    private func drawNightDisk(in context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width * 0.24, size.height * 0.40)
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

        context.fill(
            wedgePath(center: center, radius: radius, startAngle: sunriseAngle, endAngle: sunsetAngle),
            with: .linearGradient(
                Gradient(colors: [.yellow.opacity(0.30), .orange.opacity(0.18)]),
                startPoint: point(center: center, radius: radius, angle: sunriseAngle),
                endPoint: point(center: center, radius: radius, angle: sunsetAngle)
            )
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

        if let nightAngle = nightSunAngle(sunrise: sunrise, sunset: sunset, sunriseAngle: sunriseAngle, sunsetAngle: sunsetAngle) {
            drawDiskSun(in: context, at: point(center: center, radius: radius * 0.78, angle: nightAngle), radius: 6, opacity: 0.48)
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

        for pair in zip(samples, samples.dropFirst()) {
            let startAngle = sunriseAngle + CGFloat(pair.0.progress) * dayAngle
            let endAngle = sunriseAngle + CGFloat(pair.1.progress) * dayAngle
            let cloudCover = averageCloudCover(pair.0.cloudCover, pair.1.cloudCover)

            context.stroke(
                arcPath(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle),
                with: .color(cloudColor(for: cloudCover)),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawRadialLine(in context: GraphicsContext, center: CGPoint, radius: CGFloat, angle: CGFloat, color: Color) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center: center, radius: radius, angle: angle))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
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

    private func nightSunAngle(sunrise: Date?, sunset: Date?, sunriseAngle: CGFloat, sunsetAngle: CGFloat) -> CGFloat? {
        guard let sunrise, let sunset, sunset > sunrise else {
            return .pi / 2
        }

        let date = status.solar.date
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
        previewProgress ?? status.solar.daylightProgress
    }

    private func cloudPoint(at progress: Double, geometry: SolarArcGeometry) -> CGPoint {
        geometry.point(at: progress, radiusScale: 0.82)
    }

    private func averageCloudCover(_ first: Double?, _ second: Double?) -> Double {
        switch (first, second) {
        case (.some(let first), .some(let second)):
            return (first + second) / 2
        case (.some(let value), .none), (.none, .some(let value)):
            return value
        case (.none, .none):
            return status.brightness.cloudCover ?? 0
        }
    }

    private func cloudColor(for cloudCover: Double) -> Color {
        let clamped = min(max(cloudCover, 0), 1)
        let white = 0.88 - (clamped * 0.58)
        let opacity = 0.34 + (clamped * 0.48)
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
