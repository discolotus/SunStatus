import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif
#if canImport(SunStatusUI)
import SunStatusUI
#endif

#if DEBUG
private enum NightWidgetCanvasFamily {
    case small
    case medium
    case large
}

private struct SunStatusWidgetNightCanvasPreview: View {
    let status: DaylightStatus
    let family: NightWidgetCanvasFamily

    var body: some View {
        Group {
            switch family {
            case .small:
                smallContent
            case .medium:
                mediumContent
            case .large:
                largeContent
            }
        }
        .background {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(compact: true)

            SolarArcView(
                status: status,
                showsTimeLabels: false,
                arcHeight: 90,
                daylightLayout: .proportional
            )
        }
        .padding(14)
        .frame(width: 158, height: 158)
    }

    private var mediumContent: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                header(compact: false, showsLocation: true)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 5) {
                    statRow(title: "Next", value: nextTransitionValue)
                    statRow(title: "Light", value: brightnessText)
                    statRow(title: "Elevation", value: degreesText(status.solar.elevationDegrees))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            SolarArcView(
                status: status,
                showsTimeLabels: false,
                arcHeight: 108,
                daylightLayout: .proportional
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 338, height: 158)
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(compact: false, showsLocation: true)

            SolarArcView(
                status: status,
                showsTimeLabels: true,
                arcHeight: 126,
                daylightLayout: .proportional
            )

            HStack(alignment: .top, spacing: 12) {
                metric(title: "Daylight", value: daylightProgressValue)
                metric(title: "Next", value: nextTransitionValue)
                metric(title: "Light", value: brightnessText)
                metric(title: "Elevation", value: degreesText(status.solar.elevationDegrees))
            }

            Text(nextTransitionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(16)
        .frame(width: 338, height: 354)
    }

    private func header(compact: Bool, showsLocation: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: compact ? 18 : 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(status.brightness.classification.displayName)
                    .font(.system(size: compact ? 15 : 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if showsLocation {
                    Text(status.locationName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var backgroundColors: [Color] {
        switch status.brightness.classification {
        case .dark:
            [Color.indigo.opacity(0.20), Color.black.opacity(0.08)]
        case .dim:
            [Color.cyan.opacity(0.16), Color.indigo.opacity(0.14)]
        case .muted:
            [Color.yellow.opacity(0.16), Color.gray.opacity(0.10)]
        case .bright:
            [Color.yellow.opacity(0.20), Color.blue.opacity(0.10)]
        case .vivid:
            [Color.yellow.opacity(0.24), Color.orange.opacity(0.12)]
        }
    }

    private var symbolName: String {
        switch status.brightness.classification {
        case .dark:
            "moon.stars.fill"
        case .dim:
            "sun.horizon.fill"
        case .muted:
            "cloud.sun.fill"
        case .bright, .vivid:
            "sun.max.fill"
        }
    }

    private var daylightProgressText: String {
        guard let progress = status.solar.daylightProgress else {
            return "Sun below horizon"
        }

        return "\(Int((progress * 100).rounded()))% of daylight"
    }

    private var daylightProgressValue: String {
        guard let progress = status.solar.daylightProgress else {
            return "Night"
        }

        return "\(Int((progress * 100).rounded()))%"
    }

    private var nextTransitionText: String {
        guard let transition = status.nextTransition else {
            return "Night mode"
        }

        return "\(timeRemaining(until: transition.date)) until \(transition.kind.displayName)"
    }

    private var nextTransitionValue: String {
        guard let transition = status.nextTransition else {
            return "Night"
        }

        return timeRemaining(until: transition.date)
    }

    private var brightnessText: String {
        "\(Int((status.brightness.score * 100).rounded()))%"
    }

    private func degreesText(_ degrees: Double) -> String {
        "\(Int(degrees.rounded())) deg"
    }

    private func timeRemaining(until date: Date) -> String {
        let interval = max(date.timeIntervalSince(status.solar.date), 0)
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(max(minutes, 1))m"
    }
}

private enum SunStatusWidgetNightCanvasPreviewData {
    static var lateEveningStatus: DaylightStatus {
        mockStatus(hour: 22, minute: 15)
    }

    static var deepNightStatus: DaylightStatus {
        mockStatus(hour: 2, minute: 30)
    }

    static var preDawnStatus: DaylightStatus {
        mockStatus(hour: 5, minute: 20)
    }

    static var cloudShiftStatus: DaylightStatus {
        SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus(hour: 22, minute: 15)
    }

    private static func mockStatus(hour: Int, minute: Int) -> DaylightStatus {
        let timezone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timezone
        components.year = 2026
        components.month = 6
        components.day = 21
        components.hour = hour
        components.minute = minute

        let date = components.date ?? .now
        return MockDaylightProvider(timezone: timezone).status(at: date)
    }
}

#Preview("Widget Night Small Canvas", traits: .sizeThatFitsLayout) {
    SunStatusWidgetNightCanvasPreview(
        status: SunStatusWidgetNightCanvasPreviewData.lateEveningStatus,
        family: .small
    )
}

#Preview("Widget Night Medium Canvas", traits: .sizeThatFitsLayout) {
    SunStatusWidgetNightCanvasPreview(
        status: SunStatusWidgetNightCanvasPreviewData.deepNightStatus,
        family: .medium
    )
}

#Preview("Widget Night Large Canvas", traits: .sizeThatFitsLayout) {
    SunStatusWidgetNightCanvasPreview(
        status: SunStatusWidgetNightCanvasPreviewData.preDawnStatus,
        family: .large
    )
}

#Preview("Widget Night Cloud Shift Canvas", traits: .sizeThatFitsLayout) {
    SunStatusWidgetNightCanvasPreview(
        status: SunStatusWidgetNightCanvasPreviewData.cloudShiftStatus,
        family: .medium
    )
}
#endif
