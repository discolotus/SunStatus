import SwiftUI
import SunStatusCore

struct SolarArcView: View {
    let status: DaylightStatus

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let geometry = SolarArcGeometry(size: size, verticalOffset: 18)

                drawHorizon(in: context, size: size)
                drawFutureArc(in: context, geometry: geometry)
                drawCompletedArc(in: context, geometry: geometry)
                drawBrightnessArc(in: context, geometry: geometry)
                drawSun(in: context, geometry: geometry)
            }
            .frame(height: 150)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Solar arc from \(timeText(status.solar.sunrise)) to \(timeText(status.solar.sunset))")
    }

    private func drawHorizon(in context: GraphicsContext, size: CGSize) {
        var horizon = Path()
        horizon.move(to: CGPoint(x: 8, y: size.height - 18))
        horizon.addLine(to: CGPoint(x: size.width - 8, y: size.height - 18))
        context.stroke(horizon, with: .color(.secondary.opacity(0.28)), lineWidth: 1)
    }

    private func drawFutureArc(in context: GraphicsContext, geometry: SolarArcGeometry) {
        var path = Path()
        path.addLines(geometry.points(from: 0, through: 1, steps: 72))
        context.stroke(path, with: .color(.secondary.opacity(0.22)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    private func drawCompletedArc(in context: GraphicsContext, geometry: SolarArcGeometry) {
        guard let progress = status.solar.daylightProgress else {
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

    private func drawBrightnessArc(in context: GraphicsContext, geometry: SolarArcGeometry) {
        let points = status.arcPoints.sorted { $0.progress < $1.progress }
        guard points.count > 1 else {
            return
        }

        for pair in zip(points, points.dropFirst()) {
            var segment = Path()
            segment.move(to: geometry.point(at: pair.0.progress))
            segment.addLine(to: geometry.point(at: pair.1.progress))

            let averageScore = ((pair.0.brightnessScore ?? 0) + (pair.1.brightnessScore ?? 0)) / 2
            context.stroke(segment, with: .color(brightnessColor(for: averageScore)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func drawSun(in context: GraphicsContext, geometry: SolarArcGeometry) {
        guard let progress = status.solar.daylightProgress else {
            let moonPoint = CGPoint(x: geometry.size.width / 2, y: 28)
            context.fill(
                Path(ellipseIn: CGRect(x: moonPoint.x - 7, y: moonPoint.y - 7, width: 14, height: 14)),
                with: .color(.secondary.opacity(0.5))
            )
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

    private func brightnessColor(for score: Double) -> Color {
        let white = min(max(0.35 + (score * 0.6), 0.35), 0.95)
        return Color(white: white).opacity(0.95)
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
