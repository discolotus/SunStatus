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

#if DEBUG
private enum MenuBarStatusLabelPreviewData {
    static var dayStatus: DaylightStatus {
        status(hour: 13, minute: 20)
    }

    static var nightStatus: DaylightStatus {
        status(hour: 22, minute: 15)
    }

    private static func status(hour: Int, minute: Int) -> DaylightStatus {
        let timezone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let date = calendar.date(from: DateComponents(
            timeZone: timezone,
            year: 2026,
            month: 6,
            day: 21,
            hour: hour,
            minute: minute
        )) ?? Date(timeIntervalSince1970: 1_782_000_000)

        return MockDaylightProvider(timezone: timezone).status(at: date)
    }
}

#Preview("Menu Bar Label", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 10) {
        MenuBarStatusLabel(status: MenuBarStatusLabelPreviewData.dayStatus)
        MenuBarStatusLabel(status: MenuBarStatusLabelPreviewData.nightStatus)
    }
    .padding(12)
    .background(.bar, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .padding(20)
}

#Preview("Mini Solar Arc", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        MiniSolarArc(progress: 0.25)
        MiniSolarArc(progress: 0.65)
        MiniSolarArc(progress: nil)
    }
    .padding(20)
}
#endif
