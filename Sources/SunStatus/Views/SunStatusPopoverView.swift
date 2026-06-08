import AppKit
import SwiftUI
import SunStatusCore

struct SunStatusPopoverView: View {
    let status: DaylightStatus
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {
        NSApp.terminate(nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            SolarArcView(status: status)

            metrics

            modifierStrip

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
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

    private var metrics: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                MetricTile(title: "Brightness", value: "\(Int(status.brightness.score * 100))%", symbolName: "circle.lefthalf.filled")
                MetricTile(title: "UV", value: status.brightness.uvIndex.map(String.init) ?? "-", symbolName: "sun.max")
            }

            GridRow {
                MetricTile(title: "Clouds", value: percentText(status.brightness.cloudCover), symbolName: "cloud")
                MetricTile(title: "Visibility", value: visibilityText(status.brightness.visibilityMeters), symbolName: "eye")
            }
        }
    }

    private var modifierStrip: some View {
        HStack(spacing: 8) {
            ForEach(status.brightness.modifiers, id: \.self) { modifier in
                Text(modifier.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Spacer()

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
