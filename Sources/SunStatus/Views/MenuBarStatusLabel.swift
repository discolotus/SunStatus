import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif
#if canImport(SunStatusUI)
import SunStatusUI
#endif

struct MenuBarStatusLabel: View {
    let status: DaylightStatus

    var body: some View {
        HStack(spacing: 5) {
            MiniSolarArc(progress: status.solar.daylightProgress)

            if let transition = status.nextTransition {
                Text(relativeTransitionText(for: transition.date))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 2)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let transition = status.nextTransition {
            return "SunStatus, \(transition.kind.displayName) in \(relativeTransitionText(for: transition.date))"
        }

        return "SunStatus, night"
    }

    private func relativeTransitionText(for date: Date) -> String {
        let interval = max(date.timeIntervalSince(status.solar.date), 0)
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(max(minutes, 1))m"
    }
}

private struct MiniSolarArc: View {
    let progress: Double?

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let geometry = SolarArcGeometry(size: rect.size, verticalOffset: 2)
            let baselineY = size.height - 3

            var horizon = Path()
            horizon.move(to: CGPoint(x: 2, y: baselineY))
            horizon.addLine(to: CGPoint(x: size.width - 2, y: baselineY))
            context.stroke(horizon, with: .color(.secondary.opacity(0.42)), lineWidth: 1)

            var fullArc = Path()
            let allPoints = geometry.points(from: 0, through: 1, steps: 36)
            fullArc.addLines(allPoints)
            context.stroke(fullArc, with: .color(.secondary.opacity(0.32)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            if let progress {
                var completedArc = Path()
                completedArc.addLines(geometry.points(from: 0, through: progress, steps: 24))
                context.stroke(completedArc, with: .color(.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                let sunPoint = geometry.point(at: progress)
                context.fill(
                    Path(ellipseIn: CGRect(x: sunPoint.x - 2.5, y: sunPoint.y - 2.5, width: 5, height: 5)),
                    with: .color(.yellow)
                )
            } else {
                let moonRect = CGRect(x: size.width / 2 - 3, y: 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: moonRect), with: .color(.secondary.opacity(0.65)))
            }
        }
        .frame(width: 28, height: 18)
    }
}
