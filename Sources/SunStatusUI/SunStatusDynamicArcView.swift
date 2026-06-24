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
    private let status: DaylightStatus
    private let scale: SunStatusDynamicArcScale
    private let previewProgress: Double?
    private let previewDate: Date?
    private let showsTimeLabelsOverride: Bool?

    public init(
        status: DaylightStatus,
        scale: SunStatusDynamicArcScale,
        previewProgress: Double? = nil,
        previewDate: Date? = nil,
        showsTimeLabels: Bool? = nil
    ) {
        self.status = status
        self.scale = scale
        self.previewProgress = previewProgress
        self.previewDate = previewDate
        self.showsTimeLabelsOverride = showsTimeLabels
    }

    public var body: some View {
        SolarArcView(
            status: status,
            previewProgress: previewProgress,
            previewDate: previewDate,
            showsTimeLabels: showsTimeLabelsOverride ?? scale.showsTimeLabels,
            arcHeight: scale.arcHeight,
            daylightLayout: .proportional
        )
    }
}
