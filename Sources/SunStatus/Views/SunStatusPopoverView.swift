import AppKit
import SwiftUI
import SunStatusCore

struct SunStatusPopoverView: View {
    let status: DaylightStatus
    var isPinned: Bool = false
    var contentHeight: CGFloat = 560
    var onOpenSettings: () -> Void = {}
    var onOpenWindow: () -> Void = {}
    var onExpandMap: () -> Void = {}
    var onClosePinned: () -> Void = {}
    var onQuit: () -> Void = {
        NSApp.terminate(nil)
    }

    @State private var selectedPanel: PopoverPanel = .arc
    @State private var arcPreviewProgress = 0.5

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
                SolarArcView(status: status, previewProgress: arcPreviewProgress)

                arcPreviewSlider

                arcMetrics

                modifierStrip(arcPreviewModifiers)
            case .sunPath3D:
                SunPath3DPanel(status: status, onExpandMap: onExpandMap)
            }

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 380, height: contentHeight, alignment: .topLeading)
        .onAppear {
            arcPreviewProgress = status.solar.daylightProgress ?? 0.5
        }
        .onChange(of: status.solar.date) { _, _ in
            arcPreviewProgress = status.solar.daylightProgress ?? arcPreviewProgress
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(radialGradient)
                    .frame(width: 52, height: 52)

                Image(systemName: symbolName)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(status.brightness.classification.displayName)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))

                Text(nextTransitionText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(status.locationName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
    }

    private var radialGradient: RadialGradient {
        switch status.brightness.classification {
        case .dark:
            RadialGradient(colors: [.indigo, .black.opacity(0.82)], center: .center, startRadius: 2, endRadius: 40)
        case .dim:
            RadialGradient(colors: [.cyan.opacity(0.75), .indigo.opacity(0.9)], center: .topLeading, startRadius: 3, endRadius: 46)
        case .muted:
            RadialGradient(colors: [.yellow.opacity(0.72), .gray.opacity(0.72)], center: .topLeading, startRadius: 3, endRadius: 46)
        case .bright:
            RadialGradient(colors: [.yellow, .orange], center: .topLeading, startRadius: 3, endRadius: 46)
        case .vivid:
            RadialGradient(colors: [.white, .yellow, .orange], center: .topLeading, startRadius: 1, endRadius: 48)
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

            Slider(value: $arcPreviewProgress, in: 0...1) {
                Text("Preview time")
            }

            HStack {
                Text(timeText(status.arcPoints.first?.date ?? status.solar.sunrise))
                Spacer()
                Text(timeText(status.arcPoints.last?.date ?? status.solar.sunset))
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
        SunPathGeometry.sample(at: arcPreviewProgress, arcPoints: status.arcPoints, fallback: status.solar)
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
