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
            SunStatusDynamicIcon(status: status, size: 18, variant: .orb)
                .frame(width: 18, height: 18)

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

#Preview("Menu Bar Dynamic Icon", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        SunStatusDynamicIcon(status: MenuBarStatusLabelPreviewData.dayStatus, size: 18)
        SunStatusDynamicIcon(status: MenuBarStatusLabelPreviewData.nightStatus, size: 18)
    }
    .padding(20)
}
#endif
