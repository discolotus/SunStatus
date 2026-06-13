import CoreLocation
import Foundation
import SwiftUI
import WidgetKit
#if canImport(SunStatusCore)
import SunStatusCore
#endif
#if canImport(SunStatusUI)
import SunStatusUI
#endif

struct SunStatusWidgetEntry: TimelineEntry {
    let date: Date
    let status: DaylightStatus
}

final class SunStatusTimelineProvider: TimelineProvider {
    typealias Entry = SunStatusWidgetEntry

    func placeholder(in context: Context) -> SunStatusWidgetEntry {
        SunStatusWidgetEntry(date: .now, status: Self.fallbackStatus(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SunStatusWidgetEntry) -> Void) {
        completion(SunStatusWidgetEntry(date: .now, status: Self.fallbackStatus(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunStatusWidgetEntry>) -> Void) {
        let startDate = Date()

        WidgetLocationRequest.resolve { coordinate in
            let entries = Self.entries(startingAt: startDate, coordinate: coordinate)
            let reloadDate = entries.last?.date.addingTimeInterval(15 * 60) ?? startDate.addingTimeInterval(15 * 60)
            completion(Timeline(entries: entries, policy: .after(reloadDate)))
        }
    }

    private static func entries(startingAt startDate: Date, coordinate: Coordinate?) -> [SunStatusWidgetEntry] {
        let provider = provider(for: coordinate)

        return (0..<9).map { offset in
            let date = startDate.addingTimeInterval(Double(offset) * 15 * 60)
            return SunStatusWidgetEntry(date: date, status: provider.status(at: date))
        }
    }

    private static func fallbackStatus(at date: Date) -> DaylightStatus {
        provider(for: nil).status(at: date)
    }

    private static func provider(for coordinate: Coordinate?) -> SolarDaylightProvider {
        guard let coordinate else {
            return Self.sanFranciscoProvider
        }

        return SolarDaylightProvider(
            locationName: "Current Location",
            coordinate: coordinate,
            timezone: .current
        )
    }

    static var sanFranciscoProvider: SolarDaylightProvider {
        SolarDaylightProvider(
            locationName: "San Francisco",
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            timezone: TimeZone(identifier: "America/Los_Angeles") ?? .current
        )
    }
}

private final class WidgetLocationRequest: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var completion: ((Coordinate?) -> Void)?
    private var didFinish = false

    static func resolve(completion: @escaping (Coordinate?) -> Void) {
        let request = WidgetLocationRequest(completion: completion)
        request.start()
    }

    private init(completion: @escaping (Coordinate?) -> Void) {
        self.completion = completion
        super.init()
    }

    private func start() {
        DispatchQueue.main.async {
            self.manager.delegate = self
            self.manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers

            guard CLLocationManager.locationServicesEnabled() else {
                self.finish(with: nil)
                return
            }

            switch self.manager.authorizationStatus {
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.finish(with: nil)
            @unknown default:
                self.finish(with: nil)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.finish(with: nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: nil)
        case .notDetermined:
            break
        @unknown default:
            finish(with: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else {
            finish(with: nil)
            return
        }

        finish(
            with: Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }

    private func finish(with coordinate: Coordinate?) {
        guard !didFinish else {
            return
        }

        didFinish = true
        manager.delegate = nil
        let completion = completion
        self.completion = nil
        completion?(coordinate)
    }
}

struct SunStatusWidget: Widget {
    let kind = "SunStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SunStatusTimelineProvider()) { entry in
            SunStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("SunStatus")
        .description("Track the sun arc, daylight progress, and current light conditions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SunStatusDetailWidget: Widget {
    let kind = "SunStatusDetailWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SunStatusTimelineProvider()) { entry in
            SunStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("SunStatus Detail")
        .description("Track the sun arc, daylight progress, and current light conditions in a larger layout.")
        .supportedFamilies([.systemLarge])
    }
}

struct SunStatusWidgetView: View {
    let entry: SunStatusWidgetEntry
    private let previewFamily: WidgetFamily?

    @Environment(\.widgetFamily) private var family

    init(entry: SunStatusWidgetEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }

    var body: some View {
        Group {
            switch activeFamily {
            case .systemLarge:
                largeContent
            case .systemSmall:
                smallContent
            default:
                mediumContent
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var activeFamily: WidgetFamily {
        previewFamily ?? family
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(compact: true)

            SolarArcView(
                status: entry.status,
                showsTimeLabels: false,
                arcHeight: 66,
                daylightLayout: .proportional
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
    }

    private var mediumContent: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                header(compact: false, showsLocation: true)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 5) {
                    WidgetStatRow(title: "Next", value: nextTransitionValue)
                    WidgetStatRow(title: "Light", value: brightnessText)
                    WidgetStatRow(title: "Elevation", value: degreesText(entry.status.solar.elevationDegrees))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            SolarArcView(
                status: entry.status,
                showsTimeLabels: false,
                arcHeight: 108,
                daylightLayout: .proportional
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(compact: false, showsLocation: true)

            SolarArcView(
                status: entry.status,
                showsTimeLabels: true,
                arcHeight: 126,
                daylightLayout: .proportional
            )

            HStack(alignment: .top, spacing: 12) {
                WidgetMetric(title: "Daylight", value: daylightProgressValue)
                WidgetMetric(title: "Next", value: nextTransitionValue)
                WidgetMetric(title: "Light", value: brightnessText)
                WidgetMetric(title: "Elevation", value: degreesText(entry.status.solar.elevationDegrees))
            }

            Text(nextTransitionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(16)
    }

    private func header(compact: Bool, showsLocation: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: compact ? 18 : 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.status.brightness.classification.displayName)
                    .font(.system(size: compact ? 15 : 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if showsLocation {
                    Text(entry.status.locationName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var backgroundColors: [Color] {
        switch entry.status.brightness.classification {
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
        switch entry.status.brightness.classification {
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
        guard let progress = entry.status.solar.daylightProgress else {
            return "Sun below horizon"
        }

        return "\(Int((progress * 100).rounded()))% of daylight"
    }

    private var daylightProgressValue: String {
        guard let progress = entry.status.solar.daylightProgress else {
            return "Night"
        }

        return "\(Int((progress * 100).rounded()))%"
    }

    private var nextTransitionText: String {
        guard let transition = entry.status.nextTransition else {
            return "Night mode"
        }

        return "\(timeRemaining(until: transition.date)) until \(transition.kind.displayName)"
    }

    private var nextTransitionValue: String {
        guard let transition = entry.status.nextTransition else {
            return "Night"
        }

        return timeRemaining(until: transition.date)
    }

    private var brightnessText: String {
        "\(Int((entry.status.brightness.score * 100).rounded()))%"
    }

    private func degreesText(_ degrees: Double) -> String {
        "\(Int(degrees.rounded())) deg"
    }

    private func timeRemaining(until date: Date) -> String {
        let interval = max(date.timeIntervalSince(entry.status.solar.date), 0)
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(max(minutes, 1))m"
    }
}

private struct WidgetMetric: View {
    let title: String
    let value: String

    var body: some View {
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
}

private struct WidgetStatRow: View {
    let title: String
    let value: String

    var body: some View {
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
}

#if DEBUG
private enum SunStatusWidgetPreviewData {
    static let cloudShiftStatus = SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus
    static let cloudShiftEntry = SunStatusWidgetEntry(
        date: cloudShiftStatus.solar.date,
        status: cloudShiftStatus
    )
}

#Preview("Cloud Shift Small", as: .systemSmall) {
    SunStatusWidget()
} timeline: {
    SunStatusWidgetPreviewData.cloudShiftEntry
}

#Preview("Cloud Shift Medium", as: .systemMedium) {
    SunStatusWidget()
} timeline: {
    SunStatusWidgetPreviewData.cloudShiftEntry
}

#Preview("Cloud Shift Large", as: .systemLarge) {
    SunStatusDetailWidget()
} timeline: {
    SunStatusWidgetPreviewData.cloudShiftEntry
}

#Preview("Widget View - Medium", traits: .sizeThatFitsLayout) {
    SunStatusWidgetView(
        entry: SunStatusWidgetPreviewData.cloudShiftEntry,
        previewFamily: .systemMedium
    )
    .frame(width: 338, height: 158)
    .padding(20)
}

#Preview("Widget Components", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 10) {
        WidgetMetric(title: "Daylight", value: "57%")
        WidgetStatRow(title: "Clouds", value: "97%")
    }
    .frame(width: 180)
    .padding(20)
}
#endif

@main
struct SunStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        SunStatusWidget()
        SunStatusDetailWidget()
    }
}
