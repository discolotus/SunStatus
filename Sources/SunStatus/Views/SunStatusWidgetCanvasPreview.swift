import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
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
    var includesEvidenceBackdrop = true

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
        .padding(includesEvidenceBackdrop ? 24 : 0)
        .background(includesEvidenceBackdrop ? Color(nsColor: .windowBackgroundColor) : Color.clear)
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(compact: true)

            SunStatusDynamicArcView(
                status: status,
                scale: .widgetSmall
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

            SunStatusDynamicArcView(
                status: status,
                scale: .widgetMedium
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 338, height: 158)
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(compact: false, showsLocation: true)

            SunStatusDynamicArcView(
                status: status,
                scale: .widgetLarge
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
        SunStatusIdentityHeader(
            status: status,
            scale: compact ? .compact : .standard,
            showsLocation: showsLocation
        )
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

private struct SunStatusWidgetDropdownEvidence: View {
    private let status = SunStatusWidgetCanvasPreviewData.cloudShiftStatus
    private let panelBackground = Color(red: 0.95, green: 0.97, blue: 0.98)

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Widget dropdown with dynamic icons")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            HStack(alignment: .top, spacing: 30) {
                dropdownPanel
                    .frame(width: 292)

                SunStatusWidgetCanvasPreview(
                    status: status,
                    family: .medium,
                    includesEvidenceBackdrop: false
                )
            }
        }
        .padding(46)
        .frame(width: 1_120, height: 640, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color(red: 0.14, green: 0.15, blue: 0.17))
    }

    private var dropdownPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dynamic icon")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                SunStatusDynamicIcon(status: status, size: 30, variant: .orb)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Orb")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))

                    Text("Selected for widgets")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            }

            VStack(spacing: 0) {
                ForEach(SunStatusDynamicIconVariant.allCases) { variant in
                    dropdownRow(variant: variant)

                    if variant != SunStatusDynamicIconVariant.allCases.last {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        }
        .padding(18)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dropdownRow(variant: SunStatusDynamicIconVariant) -> some View {
        HStack(spacing: 10) {
            SunStatusDynamicIcon(status: status, size: 26, variant: variant)
                .frame(width: 40, height: 40)

            Text(variant.displayName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Spacer(minLength: 0)

            if variant == .orb {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if variant == .orb {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
            }
        }
    }
}

enum SunStatusWidgetDropdownEvidenceRenderer {
    @MainActor
    static func renderIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--render-widget-dropdown-pr-evidence")
            || arguments.contains("--render-popover-pr-evidence")
        else {
            return false
        }

        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let outputDirectory = root.appendingPathComponent("screenshots/pr-evidence")
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            let outputURL = outputDirectory.appendingPathComponent("dynamic-icon-widget-context.png")
            try render(outputURL: outputURL)
            print("Wrote \(outputURL.path)")
            return true
        } catch {
            fputs("Failed to render widget dropdown PR evidence: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func render(outputURL: URL) throws {
        let content = SunStatusWidgetDropdownEvidence()
            .environment(\.colorScheme, .light)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_120, height: 640)
        hostingView.wantsLayer = true
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw RenderError.missingImage
        }
        representation.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        let image = NSImage(size: hostingView.bounds.size)
        image.addRepresentation(representation)

        guard let tiffData = image.tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiffData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw RenderError.missingImage
        }

        try writePNG(cgImage, to: outputURL)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.missingDestination
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw RenderError.writeFailed
        }
    }

    private enum RenderError: Error {
        case missingImage
        case missingDestination
        case writeFailed
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

    static var cloudShiftStatus: DaylightStatus {
        SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus
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

#Preview("Widget Cloud Shift Canvas", traits: .sizeThatFitsLayout) {
    SunStatusWidgetCanvasPreview(
        status: SunStatusWidgetCanvasPreviewData.cloudShiftStatus,
        family: .medium
    )
}
#endif
