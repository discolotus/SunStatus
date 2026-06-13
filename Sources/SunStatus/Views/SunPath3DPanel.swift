import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif

struct SunPath3DPanel: View {
    let status: DaylightStatus
    var mapHeight: CGFloat = 210
    var showsExpandButton = true
    var mapMode: SunMapKitViewMode = .compact
    var onExpandMap: () -> Void = {}
    var onRecenterToUserLocation: (Coordinate) -> Void = { _ in }

    @State private var previewProgress = 0.5
    @State private var isPlayingDayPath = false
    @State private var mapKitRecenterRequestID = 0

    private let playbackTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    private let playbackDuration: TimeInterval = 10

    private var pathSamples: [SunPathSample3D] {
        SunPathGeometry.samples(from: status.arcPoints)
    }

    private var selectedSample: SunPathSample3D {
        SunPathGeometry.sample(at: previewProgress, arcPoints: status.arcPoints, fallback: status.solar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                SunMapKitView(
                    centerCoordinate: status.solar.location,
                    pathSamples: pathSamples,
                    selectedSample: selectedSample,
                    mode: mapMode,
                    recenterRequestID: mapKitRecenterRequestID,
                    onRecenterToUserLocation: onRecenterToUserLocation
                )

                VStack {
                    HStack(alignment: .top) {
                        if showsExpandButton {
                            MapExpandButton(action: onExpandMap)
                        }

                        Spacer()

                        MapRecenterButton {
                            mapKitRecenterRequestID += 1
                        }
                    }

                    Spacer()
                }
                .padding(8)
            }
            .frame(height: mapHeight)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            angleReadouts

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Button {
                        toggleDayPathPlayback()
                    } label: {
                        Image(systemName: isPlayingDayPath ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 26, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityLabel(isPlayingDayPath ? "Pause sun path animation" : "Play sun path animation")
                    .help(isPlayingDayPath ? "Pause sun path animation" : "Play sun path animation")

                    Slider(value: $previewProgress, in: 0...1) {
                        Text("Preview time")
                    }
                }

                HStack {
                    Text(timeText(pathSamples.first?.date ?? status.solar.sunrise))
                    Spacer()
                    Text(timeText(selectedSample.date))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timeText(pathSamples.last?.date ?? status.solar.sunset))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            previewProgress = status.solar.daylightProgress ?? 0.5
        }
        .onChange(of: status.solar.date) { _, _ in
            guard !isPlayingDayPath else {
                return
            }

            previewProgress = status.solar.daylightProgress ?? previewProgress
        }
        .onReceive(playbackTimer) { _ in
            advanceDayPathPlayback()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var angleReadouts: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                AngleTile(title: "Elevation", value: degreesText(selectedSample.elevationDegrees), symbolName: "arrow.up.right")
                AngleTile(title: "Azimuth", value: bearingText(selectedSample.azimuthDegrees), symbolName: "location.north.line")
            }

            GridRow {
                AngleTile(title: "Shadow", value: shadowText, symbolName: "arrow.down.left")
                AngleTile(title: "Mode", value: selectedSample.elevationDegrees > 0 ? "Day path" : "Below horizon", symbolName: "cube.transparent")
            }
        }
    }

    private var shadowText: String {
        guard let bearing = selectedSample.shadowBearingDegrees else {
            return "-"
        }

        return bearingText(bearing)
    }

    private var accessibilitySummary: String {
        "Native MapKit sun map, elevation \(degreesText(selectedSample.elevationDegrees)), azimuth \(bearingText(selectedSample.azimuthDegrees)), shadow \(shadowText)"
    }

    private func toggleDayPathPlayback() {
        if isPlayingDayPath {
            isPlayingDayPath = false
        } else {
            previewProgress = 0
            isPlayingDayPath = true
        }
    }

    private func advanceDayPathPlayback() {
        guard isPlayingDayPath else {
            return
        }

        let nextProgress = previewProgress + ((1.0 / 30.0) / playbackDuration)
        if nextProgress >= 1 {
            previewProgress = 1
            isPlayingDayPath = false
        } else {
            previewProgress = nextProgress
        }
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
}

private struct AngleTile: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minWidth: 160, minHeight: 50)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MapExpandButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
        .accessibilityLabel("Expand map")
        .help("Expand map")
    }
}

private struct MapRecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
        .accessibilityLabel("Center map on current location")
        .help("Center map on current location")
    }
}

#if DEBUG
private enum SunPath3DPanelPreviewData {
    static let status = SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus
}

#Preview("3D Panel - Compact", traits: .sizeThatFitsLayout) {
    SunPath3DPanel(
        status: SunPath3DPanelPreviewData.status,
        mapHeight: 240
    )
    .frame(width: 360)
    .padding(20)
}

#Preview("3D Panel - Expanded", traits: .sizeThatFitsLayout) {
    SunPath3DPanel(
        status: SunPath3DPanelPreviewData.status,
        mapHeight: 420,
        showsExpandButton: false,
        mapMode: .expanded
    )
    .frame(width: 760)
    .padding(20)
}

#Preview("Angle Tiles", traits: .sizeThatFitsLayout) {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
        GridRow {
            AngleTile(title: "Elevation", value: "68 deg", symbolName: "arrow.up.right")
            AngleTile(title: "Azimuth", value: "SW 214 deg", symbolName: "location.north.line")
        }
    }
    .padding(20)
}

#Preview("Map Controls", traits: .sizeThatFitsLayout) {
    HStack(spacing: 12) {
        MapExpandButton(action: {})
        MapRecenterButton(action: {})
    }
    .padding(20)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .padding(20)
}
#endif
