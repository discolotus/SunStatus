import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif

public enum SunStatusDynamicArcScale: Sendable {
    case widgetSmall
    case widgetMedium
    case widgetLarge

    var arcHeight: CGFloat {
        switch self {
        case .widgetSmall:
            90
        case .widgetMedium:
            108
        case .widgetLarge:
            126
        }
    }

    var showsTimeLabels: Bool {
        switch self {
        case .widgetSmall, .widgetMedium:
            false
        case .widgetLarge:
            true
        }
    }
}

public struct SunStatusDynamicArcView: View {
    public struct Preview: Sendable {
        let progress: Double?
        let date: Date

        public init(progress: Double?, date: Date) {
            self.progress = progress
            self.date = date
        }
    }

    private let status: DaylightStatus
    private let scale: SunStatusDynamicArcScale
    private let preview: Preview?
    private let showsTimeLabelsOverride: Bool?

    public init(
        status: DaylightStatus,
        scale: SunStatusDynamicArcScale,
        preview: Preview? = nil,
        showsTimeLabels: Bool? = nil
    ) {
        self.status = status
        self.scale = scale
        self.preview = preview
        self.showsTimeLabelsOverride = showsTimeLabels
    }

    public init(
        status: DaylightStatus,
        scale: SunStatusDynamicArcScale,
        previewProgress: Double?,
        previewDate: Date,
        showsTimeLabels: Bool? = nil
    ) {
        self.init(
            status: status,
            scale: scale,
            preview: Preview(progress: previewProgress, date: previewDate),
            showsTimeLabels: showsTimeLabels
        )
    }

    public var body: some View {
        SolarArcView(
            status: status,
            previewProgress: preview?.progress,
            previewDate: preview?.date,
            showsTimeLabels: showsTimeLabelsOverride ?? scale.showsTimeLabels,
            arcHeight: scale.arcHeight,
            daylightLayout: .proportional
        )
    }
}
