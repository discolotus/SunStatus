import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif
#if canImport(SunStatusUI)
import SunStatusUI
#endif

#if DEBUG
private enum WidgetCanvasFamily {
    case small
    case medium
    case large
}

private struct SunStatusWidgetCanvasPreview: View {
    let status: DaylightStatus
    let family: WidgetCanvasFamily

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
                arcHeight: 66
            )

            Spacer(minLength: 0)

            Text(daylightProgressText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(nextTransitionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(16)
        .frame(width: 158, height: 158)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(compact: false, showsLocation: true)

            SolarArcView(
                status: status,
                showsTimeLabels: true,
                arcHeight: 58
            )

            HStack(alignment: .top, spacing: 12) {
                metric(title: "Next", value: nextTransitionValue)
                metric(title: "Light", value: brightnessText)
                metric(title: "Elevation", value: degreesText(status.solar.elevationDegrees))
            }
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
                arcHeight: 126
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

private enum SunStatusWidgetCanvasPreviewData {
    static var morningStatus: DaylightStatus {
        status(hour: 9, minute: 15)
    }

    static var noonStatus: DaylightStatus {
        status(hour: 13, minute: 10)
    }

    static var eveningStatus: DaylightStatus {
        status(hour: 19, minute: 35)
    }

    private static func status(hour: Int, minute: Int) -> DaylightStatus {
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
        return SolarDaylightProvider(
            locationName: "San Francisco",
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            timezone: timezone
        )
        .status(at: date)
    }
}

#Preview("Widget Small Canvas", traits: .sizeThatFitsLayout) {
    SunStatusWidgetCanvasPreview(
        status: SunStatusWidgetCanvasPreviewData.morningStatus,
        family: .small
    )
}

#Preview("Widget Medium Canvas", traits: .sizeThatFitsLayout) {
    SunStatusWidgetCanvasPreview(
        status: SunStatusWidgetCanvasPreviewData.noonStatus,
        family: .medium
    )
}

#Preview("Widget Large Canvas", traits: .sizeThatFitsLayout) {
    SunStatusWidgetCanvasPreview(
        status: SunStatusWidgetCanvasPreviewData.eveningStatus,
        family: .large
    )
}
#endif
