import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif

struct PinnedSunStatusWindowView: View {
    let status: DaylightStatus
    var onExpandMap: () -> Void = {}
    var onRecenterToUserLocation: (Coordinate) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let mapHeight = max(240, proxy.size.height - 190)

            SunPath3DPanel(
                status: status,
                mapHeight: mapHeight,
                onExpandMap: onExpandMap,
                onRecenterToUserLocation: onRecenterToUserLocation
            )
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 380, height: 520)
    }
}

struct ExpandedSunMapWindowView: View {
    let status: DaylightStatus
    var onRecenterToUserLocation: (Coordinate) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let panelHeight = max(360, proxy.size.height - 250)

            ZStack(alignment: .topLeading) {
                SunPath3DPanel(
                    status: status,
                    mapHeight: panelHeight,
                    showsExpandButton: false,
                    mapMode: .expanded,
                    onRecenterToUserLocation: onRecenterToUserLocation
                )

                Text(status.locationName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(12)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: 760,
            idealWidth: 980,
            maxWidth: .infinity,
            minHeight: 700,
            idealHeight: 820,
            maxHeight: .infinity
        )
    }
}

#if DEBUG
private enum SunStatusWindowPreviewData {
    static let status = SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus
}

#Preview("Pinned SunStatus Window", traits: .sizeThatFitsLayout) {
    PinnedSunStatusWindowView(status: SunStatusWindowPreviewData.status)
}

#Preview("Expanded Sun Map Window", traits: .sizeThatFitsLayout) {
    ExpandedSunMapWindowView(status: SunStatusWindowPreviewData.status)
        .frame(width: 980, height: 820)
}
#endif
