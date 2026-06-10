import SwiftUI
import SunStatusCore

struct PinnedSunStatusWindowView: View {
    let status: DaylightStatus
    var onExpandMap: () -> Void = {}
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SunStatus")
                        .font(.headline)
                    Text(status.locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close pinned window")
            }

            SunPath3DPanel(status: status, onExpandMap: onExpandMap)
        }
        .padding(14)
        .frame(width: 380, height: 520)
    }
}

struct ExpandedSunMapWindowView: View {
    let status: DaylightStatus

    var body: some View {
        GeometryReader { proxy in
            let panelHeight = max(360, proxy.size.height - 300)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SunStatus Map")
                        .font(.title2.weight(.semibold))
                    Text(status.locationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                SunPath3DPanel(
                    status: status,
                    mapHeight: panelHeight,
                    showsExpandButton: false
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
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
