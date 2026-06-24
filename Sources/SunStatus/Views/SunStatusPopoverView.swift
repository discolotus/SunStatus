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

struct SunStatusPopoverView: View {
    let status: DaylightStatus
    var isPinned: Bool = false
    var contentHeight: CGFloat = 560
    var onOpenSettings: () -> Void = {}
    var onOpenWindow: () -> Void = {}
    var onExpandMap: () -> Void = {}
    var onRecenterToUserLocation: (Coordinate) -> Void = { _ in }
    var onClosePinned: () -> Void = {}
    var onQuit: () -> Void = {
        NSApp.terminate(nil)
    }

    @State private var selectedPanel: PopoverPanel = .arc
    @State private var arcPreviewTimelineProgress = 0.5
    @State private var isScrubbingArcPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("Panel", selection: $selectedPanel) {
                ForEach(PopoverPanel.allCases, id: \.self) { panel in
                    Label(panel.title, systemImage: panel.symbolName)
                        .tag(panel)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch selectedPanel {
            case .arc:
                SolarArcView(
                    status: status,
                    previewProgress: arcPreviewDaylightProgress,
                    previewDate: arcPreviewDate
                )

                arcPreviewSlider

                arcMetrics

                modifierStrip(arcPreviewModifiers)
            case .sunPath3D:
                SunPath3DPanel(
                    status: status,
                    onExpandMap: onExpandMap,
                    onRecenterToUserLocation: onRecenterToUserLocation
                )
            }

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 380, height: contentHeight, alignment: .topLeading)
        .onAppear {
            arcPreviewTimelineProgress = arcPreviewTimeline.currentProgress
        }
        .onChange(of: status.solar.date) { _, _ in
            guard !isScrubbingArcPreview else {
                return
            }

            arcPreviewTimelineProgress = arcPreviewTimeline.currentProgress
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            SunStatusIdentityHeader(status: status, scale: .standard, showsLocation: true)

            Text(nextTransitionText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 42)
        }
    }

    private var nextTransitionText: String {
        guard let transition = status.nextTransition else {
            return "Night mode until tomorrow"
        }

        return "\(timeRemaining(until: transition.date)) until \(transition.kind.displayName)"
    }

    private var arcPreviewSlider: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Preview time")
                Spacer()
                Text(timeText(arcPreviewSample.date))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))

            TimelineSlider(
                progress: $arcPreviewTimelineProgress,
                markers: arcPreviewSliderMarkers,
                onEditingChanged: { isEditing in
                    isScrubbingArcPreview = isEditing
                }
            )

            HStack {
                Text(timeText(arcPreviewTimeline.startDate))
                Spacer()
                Text(timeText(arcPreviewTimeline.endDate))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var arcMetrics: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                MetricTile(title: "Brightness", value: "\(Int((arcBrightnessScore * 100).rounded()))%", symbolName: "circle.lefthalf.filled")
                MetricTile(title: "Clouds", value: percentText(arcPreviewSample.cloudCover ?? status.brightness.cloudCover), symbolName: "cloud")
            }

            GridRow {
                MetricTile(title: "Elevation", value: degreesText(arcPreviewSample.elevationDegrees), symbolName: "arrow.up.right")
                MetricTile(title: "Azimuth", value: bearingText(arcPreviewSample.azimuthDegrees), symbolName: "location.north.line")
            }
        }
    }

    private func modifierStrip(_ modifiers: [BrightnessModifier]) -> some View {
        HStack(spacing: 8) {
            ForEach(modifiers, id: \.self) { modifier in
                Text(modifier.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            Spacer(minLength: 0)
        }
    }

    private var arcPreviewSample: SunPathSample3D {
        if let arcPreviewDaylightProgress {
            return SunPathGeometry.sample(at: arcPreviewDaylightProgress, arcPoints: status.arcPoints, fallback: status.solar)
        }

        let position = SolarPositionCalculator.position(at: arcPreviewDate, coordinate: status.solar.location)
        let cloudCover = status.brightness.cloudCover

        return SunPathSample3D(
            date: arcPreviewDate,
            progress: arcPreviewTimelineProgress,
            elevationDegrees: position.elevationDegrees,
            azimuthDegrees: position.azimuthDegrees,
            brightnessScore: brightnessScore(elevationDegrees: position.elevationDegrees, cloudCover: cloudCover),
            cloudCover: cloudCover
        )
    }

    private var arcPreviewTimeline: SunPathPreviewTimeline {
        SunPathPreviewTimeline(status: status)
    }

    private var arcPreviewDate: Date {
        arcPreviewTimeline.date(at: arcPreviewTimelineProgress)
    }

    private var arcPreviewDaylightProgress: Double? {
        arcPreviewTimeline.daylightProgress(for: arcPreviewDate)
    }

    private var arcPreviewSliderMarkers: [TimelineSliderMarker] {
        [
            arcPreviewTimeline.daylightStartProgress.map {
                TimelineSliderMarker(id: "sunrise", progress: $0, color: .orange.opacity(0.88))
            },
            arcPreviewTimeline.daylightEndProgress.map {
                TimelineSliderMarker(id: "sunset", progress: $0, color: .secondary.opacity(0.55))
            }
        ].compactMap { $0 }
    }

    private var arcBrightnessScore: Double {
        arcPreviewSample.brightnessScore ?? brightnessScore(
            elevationDegrees: arcPreviewSample.elevationDegrees,
            cloudCover: arcPreviewSample.cloudCover ?? status.brightness.cloudCover
        )
    }

    private var arcPreviewModifiers: [BrightnessModifier] {
        modifiers(
            elevationDegrees: arcPreviewSample.elevationDegrees,
            cloudCover: arcPreviewSample.cloudCover ?? status.brightness.cloudCover
        )
    }

    private var footer: some View {
        HStack {
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: isPinned ? onClosePinned : onOpenWindow) {
                Label(isPinned ? "Close" : "Open", systemImage: isPinned ? "xmark" : "macwindow")
            }
            .buttonStyle(.bordered)

            Button(action: onQuit) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.bordered)
        }
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return "\(Int((value * 100).rounded()))%"
    }

    private func visibilityText(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        let kilometers = value / 1_000
        return "\(Int(kilometers.rounded())) km"
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

    private func degreesText(_ degrees: Double) -> String {
        "\(Int(degrees.rounded())) deg"
    }

    private func bearingText(_ degrees: Double) -> String {
        "\(cardinalDirection(for: degrees)) \(Int(normalizedDegrees(degrees).rounded())) deg"
    }

    private func cardinalDirection(for degrees: Double) -> String {
        let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = normalizedDegrees(degrees)
        let index = Int((normalized / 45).rounded()) % labels.count
        return labels[index]
    }

    private func normalizedDegrees(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    private func brightnessScore(elevationDegrees: Double, cloudCover: Double?) -> Double {
        let clearSky: Double

        if elevationDegrees <= -6 {
            clearSky = 0.05
        } else if elevationDegrees <= 0 {
            clearSky = 0.05 + (elevationDegrees + 6) / 6 * 0.13
        } else {
            let daylight = sin(elevationDegrees * .pi / 180)
            clearSky = min(max(0.18 + daylight * 0.78, 0), 1)
        }

        guard let cloudCover else {
            return clearSky
        }

        return min(max(clearSky * (1 - cloudCover * 0.80), 0.05), 1)
    }

    private func modifiers(elevationDegrees: Double, cloudCover: Double?) -> [BrightnessModifier] {
        var result: [BrightnessModifier] = []

        if elevationDegrees <= 0 {
            result.append(.lowSun)
        } else if elevationDegrees < 8 {
            result.append(.lowSun)
            result.append(.goldenLight)
        } else {
            result.append(.highSun)
        }

        if let cloudCover {
            if cloudCover > 0.05 {
                result.append(.lightClouds)
            } else {
                result.append(.clearVisibility)
            }
        } else if elevationDegrees >= 45 {
            result.append(.clearVisibility)
        }

        return result
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

private enum PopoverPanel: CaseIterable {
    case arc
    case sunPath3D

    var title: String {
        switch self {
        case .arc: "Arc"
        case .sunPath3D: "3D"
        }
    }

    var symbolName: String {
        switch self {
        case .arc: "sun.horizon"
        case .sunPath3D: "cube.transparent"
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(minWidth: 140, minHeight: 52)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TimelineSliderMarker: Identifiable {
    let id: String
    let progress: Double
    let color: Color
}

private struct TimelineSlider: View {
    @Binding var progress: Double
    let markers: [TimelineSliderMarker]
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .leading) {
            Slider(value: $progress, in: 0...1, onEditingChanged: onEditingChanged) {
                Text("Preview time")
            }
            .labelsHidden()

            GeometryReader { proxy in
                ForEach(markers) { marker in
                    Rectangle()
                        .fill(marker.color)
                        .frame(width: 2, height: 20)
                        .clipShape(Capsule())
                        .offset(x: markerOffset(for: marker.progress, width: proxy.size.width), y: 2)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 24)
    }

    private func markerOffset(for progress: Double, width: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return min(max((width * clampedProgress) - 1, 0), max(width - 2, 0))
    }
}

#if DEBUG
private enum SunStatusPopoverPreviewData {
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

private struct TimelineSliderPreviewHost: View {
    @State private var progress = 0.55

    var body: some View {
        TimelineSlider(
            progress: $progress,
            markers: [
                TimelineSliderMarker(id: "sunrise", progress: 0.22, color: .orange),
                TimelineSliderMarker(id: "sunset", progress: 0.78, color: .secondary)
            ]
        )
        .frame(width: 300)
        .padding(20)
    }
}

private struct SunStatusPopoverCanvasPreview: View {
    let title: String
    let status: DaylightStatus
    var isPinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))

            SunStatusPopoverView(
                status: status,
                isPinned: isPinned,
                contentHeight: 560,
                onQuit: {}
            )
            .background(.ultraThinMaterial, in: PopoverPreviewShape())
            .overlay {
                PopoverPreviewShape()
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 28, y: 14)
        }
        .padding(34)
        .background {
            ZStack {
                Color.black

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.indigo.opacity(0.16),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

private struct PopoverPreviewShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 22
        let notchWidth: CGFloat = 42
        let notchHeight: CGFloat = 18
        let midX = rect.midX
        let minX = rect.minX + insetAmount
        let maxX = rect.maxX - insetAmount
        let minY = rect.minY + insetAmount
        let maxY = rect.maxY - insetAmount

        path.move(to: CGPoint(x: minX + radius, y: minY))
        path.addLine(to: CGPoint(x: midX - notchWidth * 0.5, y: minY))
        path.addQuadCurve(
            to: CGPoint(x: midX - notchWidth * 0.25, y: minY - notchHeight * 0.55),
            control: CGPoint(x: midX - notchWidth * 0.42, y: minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: midX + notchWidth * 0.25, y: minY - notchHeight * 0.55),
            control: CGPoint(x: midX, y: minY - notchHeight)
        )
        path.addQuadCurve(
            to: CGPoint(x: midX + notchWidth * 0.5, y: minY),
            control: CGPoint(x: midX + notchWidth * 0.42, y: minY)
        )
        path.addLine(to: CGPoint(x: maxX - radius, y: minY))
        path.addQuadCurve(to: CGPoint(x: maxX, y: minY + radius), control: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addQuadCurve(to: CGPoint(x: maxX - radius, y: maxY), control: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addQuadCurve(to: CGPoint(x: minX, y: maxY - radius), control: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: minY + radius))
        path.addQuadCurve(to: CGPoint(x: minX + radius, y: minY), control: CGPoint(x: minX, y: minY))
        path.closeSubpath()

        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

enum SunStatusPopoverEvidenceRenderer {
    @MainActor
    static func renderIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--render-popover-pr-evidence") else {
            return false
        }

        do {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let outputURL = root.appendingPathComponent("screenshots/pr-evidence/popover-night-canvas.png")
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try render(outputURL: outputURL)
            print("Wrote \(outputURL.path)")
            return true
        } catch {
            fputs("Failed to render popover PR evidence: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func render(outputURL: URL) throws {
        let content = SunStatusPopoverCanvasPreview(
            title: "Popover night canvas",
            status: SunStatusPopoverPreviewData.nightStatus,
            isPinned: true
        )
        .frame(width: 520, height: 760)
        .environment(\.colorScheme, .dark)
        .tint(.blue)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 760)
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

#Preview("Popover - Cloud Shift", traits: .sizeThatFitsLayout) {
    SunStatusPopoverView(
        status: SunStatusPopoverPreviewData.cloudShiftStatus,
        contentHeight: 560,
        onQuit: {}
    )
}

#Preview("Popover - Night", traits: .sizeThatFitsLayout) {
    SunStatusPopoverView(
        status: SunStatusPopoverPreviewData.nightStatus,
        isPinned: true,
        contentHeight: 560,
        onQuit: {}
    )
}

#Preview("Popover Night Canvas", traits: .sizeThatFitsLayout) {
    SunStatusPopoverCanvasPreview(
        title: "Popover night canvas",
        status: SunStatusPopoverPreviewData.nightStatus,
        isPinned: true
    )
}

#Preview("Popover Cloud Shift Canvas", traits: .sizeThatFitsLayout) {
    SunStatusPopoverCanvasPreview(
        title: "Popover cloud-shift canvas",
        status: SunStatusPopoverPreviewData.cloudShiftStatus
    )
}

#Preview("Popover Metric Tiles", traits: .sizeThatFitsLayout) {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
        GridRow {
            MetricTile(title: "Brightness", value: "82%", symbolName: "circle.lefthalf.filled")
            MetricTile(title: "Clouds", value: "97%", symbolName: "cloud")
        }
    }
    .padding(20)
}

#Preview("Timeline Slider", traits: .sizeThatFitsLayout) {
    TimelineSliderPreviewHost()
}
#endif
