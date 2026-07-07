import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif

public enum SunStatusDynamicIconVariant: String, CaseIterable, Identifiable, Sendable {
    case orb
    case horizon
    case prism

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .orb:
            return "Orb"
        case .horizon:
            return "Horizon"
        case .prism:
            return "Prism"
        }
    }
}

public struct SunStatusDynamicIcon: View {
    private let status: DaylightStatus
    private let size: CGFloat
    private let variant: SunStatusDynamicIconVariant

    public init(
        status: DaylightStatus,
        size: CGFloat = 34,
        variant: SunStatusDynamicIconVariant = .orb
    ) {
        self.status = status
        self.size = size
        self.variant = variant
    }

    public var body: some View {
        ZStack {
            backgroundSurface
            SunStatusIconArc(progress: displayProgress, palette: palette, variant: variant)
            centralLight
            cloudLayer
            glassHighlight
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var backgroundSurface: some View {
        switch variant {
        case .orb:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            palette.glow.opacity(0.96),
                            palette.surface.opacity(0.70),
                            palette.shadow.opacity(0.86)
                        ],
                        center: .topLeading,
                        startRadius: size * 0.05,
                        endRadius: size * 0.82
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(isNight ? 0.20 : 0.34), lineWidth: max(size * 0.045, 1.2))
                }
                .shadow(color: palette.shadow.opacity(0.30), radius: size * 0.14, y: size * 0.05)
        case .horizon:
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.glow.opacity(0.92),
                            palette.surface.opacity(0.68),
                            palette.shadow.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                        .strokeBorder(.white.opacity(isNight ? 0.18 : 0.32), lineWidth: max(size * 0.040, 1.1))
                }
                .shadow(color: palette.shadow.opacity(0.24), radius: size * 0.12, y: size * 0.04)
        case .prism:
            Circle()
                .fill(.clear)
                .background(
                    AngularGradient(
                        colors: [
                            palette.accent.opacity(0.62),
                            palette.glow.opacity(0.88),
                            palette.surface.opacity(0.72),
                            palette.shadow.opacity(0.78),
                            palette.accent.opacity(0.62)
                        ],
                        center: .center
                    ),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(isNight ? 0.24 : 0.38), lineWidth: max(size * 0.036, 1))
                }
                .shadow(color: palette.accent.opacity(0.20), radius: size * 0.12, y: size * 0.04)
        }
    }

    @ViewBuilder
    private var centralLight: some View {
        if isNight {
            Image(systemName: "moon.stars.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .offset(x: size * -0.015, y: size * -0.01)
                .shadow(color: palette.accent.opacity(0.42), radius: size * 0.10)
        } else {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            palette.accent.opacity(0.98),
                            palette.warm.opacity(0.96)
                        ],
                        center: .topLeading,
                        startRadius: size * 0.02,
                        endRadius: size * 0.30
                    )
                )
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(x: size * -0.06, y: size * -0.03)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.44), lineWidth: max(size * 0.032, 1))
                        .frame(width: size * 0.42, height: size * 0.42)
                        .offset(x: size * -0.06, y: size * -0.03)
                }
                .shadow(color: palette.warm.opacity(0.50), radius: size * 0.13)
        }
    }

    @ViewBuilder
    private var cloudLayer: some View {
        if !isNight, cloudVisibility > 0.04 {
            Image(systemName: "cloud.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            Color(white: 0.80).opacity(0.82),
                            palette.shadow.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.28 + (cloudVisibility * 0.64))
                .offset(x: size * 0.10, y: size * 0.11)
                .shadow(color: palette.shadow.opacity(0.20 + (cloudVisibility * 0.34)), radius: size * 0.09)
        } else if isNight, cloudVisibility > 0.16 {
            Image(systemName: "cloud.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42 + (cloudVisibility * 0.32)))
                .offset(x: size * 0.10, y: size * 0.12)
                .shadow(color: .black.opacity(0.22), radius: size * 0.08)
        }
    }

    private var glassHighlight: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isNight ? 0.24 : 0.42),
                        Color.white.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .scaleEffect(x: variant == .horizon ? 1.06 : 0.88, y: 0.58)
            .offset(y: size * -0.19)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private var palette: SunStatusIconPalette {
        SunStatusIconPalette(classification: status.brightness.classification, isNight: isNight)
    }

    private var isNight: Bool {
        status.solar.daylightProgress == nil
    }

    private var displayProgress: Double {
        status.solar.daylightProgress ?? 0.76
    }

    private var cloudVisibility: Double {
        min(max(status.brightness.cloudCover ?? 0, 0), 1)
    }

    private var accessibilityLabel: String {
        if isNight {
            return "Night light icon"
        }

        return "SunStatus light icon, \(Int((displayProgress * 100).rounded())) percent through daylight"
    }
}

public enum SunStatusIdentityHeaderScale: Sendable {
    case compact
    case standard

    var iconSize: CGFloat {
        switch self {
        case .compact:
            30
        case .standard:
            34
        }
    }

    var titleSize: CGFloat {
        switch self {
        case .compact:
            15
        case .standard:
            17
        }
    }
}

public struct SunStatusIdentityHeader: View {
    private let status: DaylightStatus
    private let scale: SunStatusIdentityHeaderScale
    private let showsLocation: Bool

    public init(
        status: DaylightStatus,
        scale: SunStatusIdentityHeaderScale = .standard,
        showsLocation: Bool = false
    ) {
        self.status = status
        self.scale = scale
        self.showsLocation = showsLocation
    }

    public var body: some View {
        HStack(spacing: 8) {
            SunStatusDynamicIcon(status: status, size: scale.iconSize, variant: .orb)
                .frame(width: scale.iconSize, height: scale.iconSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(status.brightness.classification.displayName)
                    .font(.system(size: scale.titleSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if showsLocation {
                    Text(status.locationName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SunStatusIconPalette {
    let glow: Color
    let surface: Color
    let shadow: Color
    let accent: Color
    let warm: Color

    init(classification: BrightnessClassification, isNight: Bool) {
        if isNight {
            glow = Color(red: 0.34, green: 0.30, blue: 0.76)
            surface = Color(red: 0.12, green: 0.14, blue: 0.32)
            shadow = Color(red: 0.03, green: 0.04, blue: 0.12)
            accent = Color(red: 0.62, green: 0.56, blue: 1.0)
            warm = Color(red: 1.0, green: 0.67, blue: 0.22)
            return
        }

        switch classification {
        case .dark:
            glow = Color(red: 0.30, green: 0.36, blue: 0.72)
            surface = Color(red: 0.12, green: 0.16, blue: 0.34)
            shadow = Color(red: 0.04, green: 0.05, blue: 0.14)
            accent = Color(red: 0.80, green: 0.76, blue: 1.0)
            warm = Color(red: 1.0, green: 0.64, blue: 0.18)
        case .dim:
            glow = Color(red: 0.42, green: 0.78, blue: 0.92)
            surface = Color(red: 0.33, green: 0.50, blue: 0.82)
            shadow = Color(red: 0.12, green: 0.13, blue: 0.34)
            accent = Color(red: 1.0, green: 0.78, blue: 0.18)
            warm = Color(red: 1.0, green: 0.46, blue: 0.10)
        case .muted:
            glow = Color(red: 0.98, green: 0.80, blue: 0.34)
            surface = Color(red: 0.72, green: 0.74, blue: 0.70)
            shadow = Color(red: 0.30, green: 0.30, blue: 0.34)
            accent = Color(red: 1.0, green: 0.82, blue: 0.18)
            warm = Color(red: 0.98, green: 0.50, blue: 0.10)
        case .bright:
            glow = Color(red: 1.0, green: 0.86, blue: 0.26)
            surface = Color(red: 0.84, green: 0.92, blue: 0.96)
            shadow = Color(red: 0.34, green: 0.44, blue: 0.66)
            accent = Color(red: 1.0, green: 0.82, blue: 0.05)
            warm = Color(red: 1.0, green: 0.50, blue: 0.08)
        case .vivid:
            glow = Color.white
            surface = Color(red: 1.0, green: 0.88, blue: 0.24)
            shadow = Color(red: 0.56, green: 0.28, blue: 0.06)
            accent = Color(red: 1.0, green: 0.84, blue: 0.04)
            warm = Color(red: 1.0, green: 0.44, blue: 0.04)
        }
    }
}

private struct SunStatusIconArc: View {
    let progress: Double
    let palette: SunStatusIconPalette
    let variant: SunStatusDynamicIconVariant

    var body: some View {
        Canvas { context, size in
            let minSide = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = minSide * (variant == .horizon ? 0.35 : 0.42)
            let startAngle = Angle(degrees: 205)
            let endAngle = Angle(degrees: -25)
            let clampedProgress = min(max(progress, 0), 1)
            let currentAngle = 205 + ((-25 - 205) * clampedProgress)

            var track = Path()
            track.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            context.stroke(
                track,
                with: .color(.white.opacity(0.26)),
                style: StrokeStyle(lineWidth: max(minSide * 0.050, 1.4), lineCap: .round)
            )

            var active = Path()
            active.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: Angle(degrees: currentAngle),
                clockwise: false
            )
            context.stroke(
                active,
                with: .linearGradient(
                    Gradient(colors: [
                        palette.warm.opacity(0.95),
                        palette.accent.opacity(0.98)
                    ]),
                    startPoint: CGPoint(x: center.x - radius, y: center.y + radius),
                    endPoint: CGPoint(x: center.x + radius, y: center.y - radius)
                ),
                style: StrokeStyle(lineWidth: max(minSide * 0.062, 1.8), lineCap: .round)
            )

            let marker = point(center: center, radius: radius, angleDegrees: currentAngle)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: marker.x - minSide * 0.045,
                    y: marker.y - minSide * 0.045,
                    width: minSide * 0.09,
                    height: minSide * 0.09
                )),
                with: .color(palette.accent.opacity(0.95))
            )
        }
        .allowsHitTesting(false)
    }

    private func point(center: CGPoint, radius: CGFloat, angleDegrees: Double) -> CGPoint {
        let radians = CGFloat(angleDegrees * .pi / 180)
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

#if DEBUG
private enum SunStatusDynamicIconPreviewData {
    static let cloudShiftStatus = SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus
    static let nightStatus = SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus(hour: 22, minute: 15)
}

#Preview("Dynamic Icon Variants", traits: .sizeThatFitsLayout) {
    HStack(spacing: 18) {
        ForEach(SunStatusDynamicIconVariant.allCases) { variant in
            VStack(spacing: 8) {
                SunStatusDynamicIcon(
                    status: SunStatusDynamicIconPreviewData.cloudShiftStatus,
                    size: 56,
                    variant: variant
                )

                Text(variant.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(24)
}

#Preview("Dynamic Icon Day Night", traits: .sizeThatFitsLayout) {
    HStack(spacing: 18) {
        SunStatusDynamicIcon(status: SunStatusDynamicIconPreviewData.cloudShiftStatus, size: 56)
        SunStatusDynamicIcon(status: SunStatusDynamicIconPreviewData.nightStatus, size: 56)
    }
    .padding(24)
}
#endif
