//
//  DesignSystem.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import UIKit
import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: PMLocalized("System")
        case .light: PMLocalized("Light")
        case .dark: PMLocalized("Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum PayGuardTheme {
    private static func uiColor(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    // Palette is taken from the supplied app icons, but the app surfaces are tuned
    // toward a premium graphite / smoked-black look in dark mode.
    // Light mode keeps the light icon's blue-gray + navy + teal identity.
    static let midnight = dynamicColor(
        light: uiColor(0x244A78),
        dark: uiColor(0x05070D)
    )
    static let ocean = dynamicColor(
        light: uiColor(0x1C5A96),
        dark: uiColor(0x172A44)
    )
    static let seafoam = dynamicColor(
        light: uiColor(0x42B7BF),
        dark: uiColor(0x43D6CF)
    )
    static let accent = dynamicColor(
        light: uiColor(0x42B7BF),
        dark: uiColor(0x43D6CF)
    )
    static let sky = dynamicColor(
        light: uiColor(0xDDE8F5),
        dark: uiColor(0x182130)
    )

    static let background = dynamicColor(
        light: uiColor(0xEEF4FA),
        dark: uiColor(0x05070D)
    )
    static let backgroundSecondary = dynamicColor(
        light: uiColor(0xE3EDF7),
        dark: uiColor(0x080D15)
    )
    static let surface = dynamicColor(
        light: uiColor(0xFBFDFF, alpha: 0.90),
        dark: uiColor(0x111823, alpha: 0.98)
    )
    static let surfaceSecondary = dynamicColor(
        light: uiColor(0xF3F7FC, alpha: 0.96),
        dark: uiColor(0x1A2330, alpha: 0.98)
    )
    static let inputFill = dynamicColor(
        light: uiColor(0xF7FAFD, alpha: 0.98),
        dark: uiColor(0x101722, alpha: 0.98)
    )
    static let surfaceStrong = dynamicColor(
        light: uiColor(0x244A78),
        dark: uiColor(0x202A38)
    )
    static let textPrimary = dynamicColor(
        light: uiColor(0x142B44),
        dark: uiColor(0xEAF2FF)
    )
    static let navigationTitle = dynamicColor(
        light: uiColor(0x1F9FAF),
        dark: uiColor(0x43D6CF)
    )
    static let textSecondary = dynamicColor(
        light: uiColor(0x5B6F86),
        dark: uiColor(0xA6B3C5)
    )
    static let stroke = dynamicColor(
        light: uiColor(0xFFFFFF, alpha: 0.82),
        dark: uiColor(0x2B3544, alpha: 0.72)
    )
    static let divider = dynamicColor(
        light: uiColor(0xC4D1DF, alpha: 0.90),
        dark: uiColor(0x2E3948, alpha: 0.58)
    )
    static let shadow = dynamicColor(
        light: uiColor(0x244A78, alpha: 0.14),
        dark: uiColor(0x000000, alpha: 0.42)
    )
    static let positive = dynamicColor(
        light: uiColor(0x1F6A80),
        dark: uiColor(0x43D6CF)
    )
    static let warning = dynamicColor(
        light: uiColor(0xA8791F),
        dark: uiColor(0xF1C75E)
    )
    static let destructive = dynamicColor(
        light: uiColor(0xB73A48),
        dark: uiColor(0xFF6B76)
    )

    static let titleFont = Font.system(.title2, design: .rounded, weight: .bold)
    static let bodyFont = Font.system(.body, design: .rounded)
    static let captionFont = Font.system(.subheadline, design: .rounded)
}

struct PayGuardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(PayGuardPremiumCardBackground(cornerRadius: 28))
    }
}

struct PayGuardPremiumCardBackground: View {
    var cornerRadius: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        PayGuardTheme.surfaceSecondary.opacity(0.94),
                        PayGuardTheme.surface.opacity(0.98),
                        PayGuardTheme.backgroundSecondary.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.10),
                                PayGuardTheme.stroke,
                                PayGuardTheme.accent.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: PayGuardTheme.shadow.opacity(0.52), radius: 14, x: 0, y: 8)
    }
}

struct PayGuardBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PayGuardTheme.background, PayGuardTheme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(PayGuardTheme.accent.opacity(0.07))
                .frame(width: 280, height: 280)
                .blur(radius: 52)
                .offset(x: -150, y: -280)

            Circle()
                .fill(PayGuardTheme.ocean.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 60)
                .offset(x: 180, y: 270)
        }
    }
}

struct SectionTitleView: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.pmLocalized.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.accent)
            Text(title.localizedKey)
                .font(PayGuardTheme.titleFont)
                .foregroundStyle(PayGuardTheme.textPrimary)
            Text(detail.localizedKey)
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)
        }
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [PayGuardTheme.ocean, PayGuardTheme.accent, PayGuardTheme.seafoam],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: PayGuardTheme.accent.opacity(0.28), radius: 22, x: 0, y: 14)
    }
}

struct SecondaryChip: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title.localizedKey, systemImage: symbol)
            .font(.system(.footnote, design: .rounded, weight: .medium))
            .foregroundStyle(PayGuardTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(PayGuardTheme.surfaceSecondary)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(PayGuardTheme.stroke, lineWidth: 1)
            }
    }
}

struct PayGuardPanel<Content: View>: View {
    let title: String
    let symbol: String
    let detail: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        symbol: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title.localizedKey, systemImage: symbol)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)

                if let detail {
                    Text(detail.localizedKey)
                        .font(PayGuardTheme.captionFont)
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
            }

            content
        }
        .payGuardCardStyle()
    }
}

struct PayGuardMetricBadge: View {
    let title: String
    let value: String
    var accent: Color = PayGuardTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.pmLocalized.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textSecondary)
            Text(value.localizedKey)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PayGuardTheme.inputFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        }
    }
}

struct PayGuardKeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title.localizedKey)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(PayGuardTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value.localizedKey)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}


struct PremiumDetailMetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PayGuardTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title.pmLocalized.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                Text(value.localizedKey)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PayGuardTheme.surface.opacity(0.92))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [PayGuardTheme.stroke, PayGuardTheme.accent.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

struct PremiumDetailPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PayGuardTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))
                Text(title.localizedKey)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Spacer(minLength: 0)
            }

            content
        }
        .padding(18)
        .background(PayGuardPremiumCardBackground(cornerRadius: 28))
    }
}

struct PremiumDetailKeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title.localizedKey)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(PayGuardTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value.localizedKey)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct PremiumDetailDivider: View {
    var body: some View {
        Rectangle()
            .fill(PayGuardTheme.divider.opacity(0.58))
            .frame(height: 1)
    }
}

struct PremiumNoteBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(PayGuardTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PayGuardTheme.inputFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PayGuardTheme.stroke, lineWidth: 1)
            }
    }
}

struct PremiumInsightRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 5) {
                Text(title.localizedKey)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(detail.localizedKey)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(PayGuardTheme.inputFill.opacity(0.92))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}

struct PayGuardNavigationRow: View {
    let title: String
    let detail: String
    let value: String?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.localizedKey)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(detail.localizedKey)
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }

            Spacer(minLength: 12)

            if let value {
                Text(value.localizedKey)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}

struct PayGuardTag: View {
    let title: String
    var accent: Color = PayGuardTheme.accent

    var body: some View {
        Text(title.localizedKey)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.12))
            )
    }
}

struct PremiumLanguagePicker: View {
    let title: String?
    let detail: String?
    @Binding var selection: AppLanguage

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        title: String? = nil,
        detail: String? = nil,
        selection: Binding<AppLanguage>
    ) {
        self.title = title
        self.detail = detail
        self._selection = selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.localizedKey)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(PayGuardTheme.textPrimary)

                    if let detail {
                        Text(detail.localizedKey)
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selection = language
                        }
                    } label: {
                        PremiumLanguageCard(
                            language: language,
                            isSelected: selection == language
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PremiumLanguageCard: View {
    let language: AppLanguage
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(language.flag)
                .font(.system(size: 28))

            Text(language.displayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : PayGuardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(language.shortLabel)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white.opacity(0.82) : PayGuardTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? .white.opacity(0.18) : PayGuardTheme.accent.opacity(0.10))
                )
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 106)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: shadowColor, radius: isSelected ? 18 : 0, x: 0, y: isSelected ? 10 : 0)
        .scaleEffect(isSelected ? 1 : 0.985)
    }

    private var background: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [PayGuardTheme.ocean, PayGuardTheme.accent, PayGuardTheme.seafoam],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [PayGuardTheme.surfaceSecondary, PayGuardTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var borderColor: Color {
        isSelected ? .white.opacity(0.28) : PayGuardTheme.stroke
    }

    private var shadowColor: Color {
        isSelected ? PayGuardTheme.accent.opacity(0.24) : .clear
    }
}

enum PayGuardBadgeTone {
    case critical
    case warning
    case positive
    case accent

    var color: Color {
        switch self {
        case .critical:
            PayGuardTheme.destructive
        case .warning:
            PayGuardTheme.warning
        case .positive:
            PayGuardTheme.positive
        case .accent:
            PayGuardTheme.accent
        }
    }
}

struct PremiumStatusBadge: View {
    let title: String
    let value: String
    let tone: PayGuardBadgeTone
    var systemName: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tone.color, tone.color.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .fill(.white.opacity(0.92))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 22, height: 22)
            .shadow(color: tone.color.opacity(0.30), radius: 10, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.pmLocalized.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(tone.color)
                Text(value)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tone.color.opacity(0.18),
                            PayGuardTheme.surfaceSecondary.opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tone.color.opacity(0.28), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.14), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .shadow(color: tone.color.opacity(0.10), radius: 14, x: 0, y: 8)
    }
}

struct ToolbarCircleIcon: View {
    let systemName: String
    var emphasized: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(emphasized ? .white : PayGuardTheme.textPrimary)
            .frame(width: 38, height: 38)
            .background(backgroundStyle)
            .overlay {
                Circle()
                    .stroke(emphasized ? .white.opacity(0.14) : PayGuardTheme.stroke, lineWidth: 1)
            }
            .shadow(
                color: emphasized ? PayGuardTheme.accent.opacity(0.26) : PayGuardTheme.shadow.opacity(0.55),
                radius: emphasized ? 14 : 10,
                x: 0,
                y: emphasized ? 8 : 5
            )
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        if emphasized {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PayGuardTheme.ocean, PayGuardTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            Circle()
                .fill(PayGuardTheme.surfaceSecondary)
        }
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(PayGuardTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PayGuardTheme.surfaceSecondary)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PayGuardTheme.stroke, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct DestructiveActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(PayGuardTheme.destructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PayGuardTheme.destructive.opacity(0.10))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PayGuardTheme.destructive.opacity(0.22), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct PayGuardTextInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(PayGuardTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PayGuardTheme.inputFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PayGuardTheme.stroke, lineWidth: 1)
            }
    }
}

struct PayGuardListSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSpacing(18)
    }
}

struct PayGuardNavigationChromeModifier: ViewModifier {
    init() {
        Self.configureNavigationBarAppearance()
    }

    func body(content: Content) -> some View {
        content
            .toolbarBackground(PayGuardTheme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private static let navigationBarAppearanceConfigured: Void = {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(PayGuardTheme.background.opacity(0.96))
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(PayGuardTheme.navigationTitle),
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(PayGuardTheme.navigationTitle),
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.prefersLargeTitles = true
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.tintColor = UIColor(PayGuardTheme.navigationTitle)
    }()

    private static func configureNavigationBarAppearance() {
        _ = navigationBarAppearanceConfigured
    }
}

struct HeroPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(22)
            .background(
                LinearGradient(
                    colors: [
                        PayGuardTheme.surfaceStrong.opacity(0.96),
                        PayGuardTheme.ocean.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: PayGuardTheme.shadow.opacity(1), radius: 26, x: 0, y: 18)
    }
}

extension View {
    func payGuardHeroStyle() -> some View {
        modifier(HeroPanel())
    }
}
