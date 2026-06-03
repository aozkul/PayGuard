//
//  OnboardingFlowView.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import SwiftUI
import UserNotifications

struct OnboardingFlowView: View {
    private static let totalSteps = 8

    let onComplete: (Bool) -> Void

    @StateObject private var notificationState = NotificationPermissionState()
    @AppStorage(AppLanguage.storageKey) private var selectedLanguageRaw = AppLanguage.fallback.rawValue

    @State private var step = 0
    @State private var defaultCurrency = "EUR"
    @State private var wantsNotifications = false
    @State private var wantsFamilySpace = true
    @State private var wantsWarrantyTracking = true
    @State private var includeSampleData = false
    @State private var isRequestingNotifications = false

    private var selectedLanguage: AppLanguage {
        get { AppLanguage(rawValue: selectedLanguageRaw) ?? .fallback }
        nonmutating set { selectedLanguageRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack {
            PayGuardBackdrop()

            VStack(spacing: 24) {
                HStack {
                    Capsule()
                        .fill(PayGuardTheme.accent.opacity(0.18))
                        .frame(width: 96, height: 7)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [PayGuardTheme.ocean, PayGuardTheme.accent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 96 * CGFloat(step + 1) / CGFloat(Self.totalSteps), height: 7)
                        }
                    Spacer()
                    Text(PMLocalized("Step %d / %d", step + 1, Self.totalSteps))
                        .textCase(nil)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }

                TabView(selection: $step) {
                    onboardingWelcome.tag(0)
                    languageSetup.tag(1)
                    currencySetup.tag(2)
                    emailImportSetup.tag(3)
                    preferenceSetup.tag(4)
                    notificationSetup.tag(5)
                    widgetSetup.tag(6)
                    finishSetup.tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 12) {
                    if step > 0 {
                        Button(PMLocalized("Back")) {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                                step -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(step == Self.totalSteps - 1 ? PMLocalized("Open PayGuard") : PMLocalized("Continue")) {
                        continueFlow()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
            }
            .padding(24)
        }
        .task {
            await notificationState.refresh()
        }
        .onChange(of: wantsNotifications) { _, enabled in
            guard enabled else { return }
            Task {
                isRequestingNotifications = true
                _ = await NotificationScheduler.shared.requestPermission()
                await notificationState.refresh()
                isRequestingNotifications = false
            }
        }
    }

    private func onboardingStage<Content: View>(
        eyebrow: String,
        title: String,
        detail: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [PayGuardTheme.ocean.opacity(0.98), PayGuardTheme.accent.opacity(0.90)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 68, height: 68)
                            .shadow(color: PayGuardTheme.accent.opacity(0.22), radius: 18, x: 0, y: 12)

                        Image(systemName: symbol)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(eyebrow.pmLocalized.uppercased())
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(PayGuardTheme.accent)
                            .tracking(0.8)
                        Text(title.localizedKey)
                            .font(.system(.title2, design: .rounded, weight: .heavy))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail.localizedKey)
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .background(PayGuardPremiumCardBackground(cornerRadius: 30))

                content()
            }
            .padding(.vertical, 4)
        }
    }

    private var onboardingWelcome: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [PayGuardTheme.accent.opacity(0.28), PayGuardTheme.ocean.opacity(0.14), .clear],
                            center: .center,
                            startRadius: 18,
                            endRadius: 132
                        )
                    )
                    .frame(width: 232, height: 232)
                    .blur(radius: 3)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [PayGuardTheme.surfaceStrong.opacity(0.98), PayGuardTheme.surface.opacity(0.94)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 184, height: 184)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: PayGuardTheme.accent.opacity(0.28), radius: 30, x: 0, y: 20)

                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 138, height: 138)
                    .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 14)
            }
            .accessibilityHidden(true)

            VStack(spacing: 9) {
                Text("PayGuard")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .minimumScaleFactor(0.85)

                Text("Your private command center for subscriptions, receipts, renewals, warranties and reminders.".localizedKey)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            VStack(spacing: 10) {
                onboardingCompactFeature(
                    title: "Find recurring costs",
                    detail: "Lifetime Pro scans connected mailboxes for recurring charges and opens clean drafts for review.",
                    symbol: "mail.stack.fill"
                )
                onboardingCompactFeature(
                    title: "Stay ahead of charges",
                    detail: "Premium reminders help you act before renewals, returns and warranties expire.",
                    symbol: "bell.badge.fill"
                )
            }
            .padding(.top, 2)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var languageSetup: some View {
        onboardingStage(
            eyebrow: "Language",
            title: "Choose the language PayGuard should speak.",
            detail: "This choice updates onboarding, settings, records and reminders immediately.",
            symbol: "globe.europe.africa.fill"
        ) {
            PremiumLanguagePicker(
                title: "Available languages",
                detail: "Select the language that feels most comfortable.",
                selection: Binding(
                    get: { selectedLanguage },
                    set: { selectedLanguage = $0 }
                )
            )
            .padding(16)
            .background(PayGuardPremiumCardBackground(cornerRadius: 28))
        }
    }

    private var currencySetup: some View {
        onboardingStage(
            eyebrow: "Currency",
            title: "Set the money view for your dashboard.",
            detail: "This becomes the default for new subscriptions, protected purchases, totals, and imported suggestions.",
            symbol: "eurosign.circle.fill"
        ) {
            PremiumCurrencyPicker(selection: $defaultCurrency)
        }
    }

    private var emailImportSetup: some View {
        onboardingStage(
            eyebrow: "Premium email discovery",
            title: "Unlock recurring subscriptions from your inbox.",
            detail: "Lifetime Pro connects to your mailboxes from Settings, scans for weekly, monthly, and yearly charges, and opens prefilled drafts before anything is saved.",
            symbol: "envelope.badge.shield.half.filled"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SecondaryChip(title: "Lifetime Pro", symbol: "sparkles")
                    SecondaryChip(title: "Recurring only", symbol: "repeat")
                    SecondaryChip(title: "Review before save", symbol: "checkmark.shield.fill")
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    onboardingValueCard(
                        title: "Auto scan",
                        detail: "Search connected inboxes for paid recurring subscriptions with clear billing cycles.",
                        symbol: "waveform.path.ecg.rectangle.fill"
                    )
                    onboardingValueCard(
                        title: "Direct editor",
                        detail: "Open each detected subscription in the editor and fix fields before saving.",
                        symbol: "square.and.pencil"
                    )
                }
            }

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    OnboardingEmailSourceCard(title: "Gmail", symbol: "envelope.fill")
                    OnboardingEmailSourceCard(title: "iCloud", symbol: "icloud.fill")
                }

                HStack(spacing: 12) {
                    OnboardingEmailSourceCard(title: "Outlook", symbol: "briefcase.fill")
                    OnboardingEmailSourceCard(title: "Any IMAP", symbol: "mail.stack.fill")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                onboardingCheckRow(title: "Connect Gmail, iCloud Mail, Outlook, Yahoo, Proton Bridge, or IMAP in Settings", symbol: "gearshape.fill")
                onboardingCheckRow(title: "PayGuard only keeps weekly, monthly, or yearly subscriptions with real payment signals", symbol: "line.3.horizontal.decrease.circle.fill")
                onboardingCheckRow(title: "Each match opens in the editor before anything is saved", symbol: "checkmark.seal.fill")
            }
            .padding(16)
            .background(PayGuardPremiumCardBackground(cornerRadius: 24))
        }
    }

    private var preferenceSetup: some View {
        onboardingStage(
            eyebrow: "Tracking scope",
            title: "Choose the protection layers you want ready.",
            detail: "Start lean, or prepare PayGuard for family ownership, purchases, returns and a demo dashboard.",
            symbol: "slider.horizontal.3"
        ) {
            VStack(spacing: 12) {
                TrackingScopeOptionCard(
                    title: "Family space",
                    detail: "Separate owners, payers and household spending without clutter.",
                    symbol: "person.2.crop.square.stack.fill",
                    isOn: $wantsFamilySpace
                )
                TrackingScopeOptionCard(
                    title: "Warranty and returns",
                    detail: "Keep purchase receipts, return windows and warranty dates together.",
                    symbol: "shield.checkered",
                    isOn: $wantsWarrantyTracking
                )
                TrackingScopeOptionCard(
                    title: "Sample dashboard",
                    detail: "Add example records so the first dashboard already feels alive.",
                    symbol: "sparkles.rectangle.stack.fill",
                    isOn: $includeSampleData
                )
            }
        }
    }

    private var notificationSetup: some View {
        onboardingStage(
            eyebrow: "Smart alerts",
            title: "Premium reminders before money leaves your account.",
            detail: "Choose PayGuard alerts now. You can still adjust notification preferences later from Settings.",
            symbol: "bell.badge.fill"
        ) {
            VStack(spacing: 14) {
                notificationPremiumControl
                notificationTimelinePreview
            }
        }
    }

    private var notificationPremiumControl: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PayGuardTheme.ocean, PayGuardTheme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: PayGuardTheme.accent.opacity(0.24), radius: 18, x: 0, y: 12)

                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.system(size: 23, weight: .heavy))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Renewal protection".localizedKey)
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    Text(wantsNotifications ? permissionSummary : PMLocalized("Off by default"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(wantsNotifications ? PayGuardTheme.accent : PayGuardTheme.textSecondary)
                }

                Spacer(minLength: 0)

                if isRequestingNotifications {
                    ProgressView()
                        .tint(PayGuardTheme.accent)
                }

                Toggle("", isOn: $wantsNotifications)
                    .labelsHidden()
                    .tint(PayGuardTheme.accent)
            }

            Text("Keep this off to continue without alerts. When you switch it on, PayGuard asks for notification permission immediately.".localizedKey)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PayGuardTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(PayGuardPremiumCardBackground(cornerRadius: 28))
    }

    private var notificationTimelinePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reminder timeline".localizedKey)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(PayGuardTheme.accent)
                .tracking(0.8)

            HStack(spacing: 10) {
                notificationTimelineItem(title: "7 days", detail: "Plan", symbol: "calendar.badge.clock")
                notificationTimelineItem(title: "3 days", detail: "Check", symbol: "exclamationmark.bubble.fill")
                notificationTimelineItem(title: "1 day", detail: "Act", symbol: "bolt.fill")
            }
        }
        .padding(16)
        .background(PayGuardPremiumCardBackground(cornerRadius: 26))
    }

    private func notificationTimelineItem(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))
            Text(title.localizedKey)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(PayGuardTheme.textPrimary)
            Text(detail.localizedKey)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(PayGuardTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PayGuardTheme.surfaceSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var widgetSetup: some View {
        onboardingStage(
            eyebrow: "Widgets",
            title: "Add a premium glance layer later.",
            detail: "Widgets come after the core setup because they work best once you have renewals, receipts, or purchase deadlines to show.",
            symbol: "square.grid.2x2.fill"
        ) {
            OnboardingWidgetShowcase()

            HStack(spacing: 10) {
                SecondaryChip(title: "Monthly total", symbol: "chart.pie.fill")
                SecondaryChip(title: "Next deadline", symbol: "calendar.badge.clock")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var finishSetup: some View {
        onboardingStage(
            eyebrow: "Ready",
            title: "PayGuard is prepared around your choices.",
            detail: "Open the dashboard, add the first subscription, connect mailboxes from Settings, or start with the sample data option you selected.",
            symbol: "checkmark.seal.fill"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                summaryRow("Default currency", value: defaultCurrency)
                summaryRow("App language", value: selectedLanguage.selectionLabel)
                summaryRow("Notifications", value: wantsNotifications ? permissionSummary : PMLocalized("Skipped"))
                summaryRow("Family space", value: wantsFamilySpace ? PMLocalized("Enabled") : PMLocalized("Can enable later"))
                summaryRow("Warranty tracking", value: wantsWarrantyTracking ? PMLocalized("Enabled") : PMLocalized("Can enable later"))
                summaryRow("Email auto scan", value: PMLocalized("Premium feature in Settings"))
                summaryRow("Sample data", value: includeSampleData ? PMLocalized("Included") : PMLocalized("Start empty"))
            }
            .padding(18)
            .background(PayGuardPremiumCardBackground(cornerRadius: 26))
        }
    }

    private func premiumWelcomePill(title: String, symbol: String) -> some View {
        Label(title.localizedKey, systemImage: symbol)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(PayGuardTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(PayGuardTheme.surfaceStrong.opacity(0.78))
            )
            .overlay {
                Capsule()
                    .stroke(PayGuardTheme.accent.opacity(0.18), lineWidth: 1)
            }
    }

    private func onboardingCompactFeature(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    LinearGradient(
                        colors: [PayGuardTheme.ocean, PayGuardTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title.localizedKey)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(detail.localizedKey)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(PayGuardPremiumCardBackground(cornerRadius: 22))
    }

    private func onboardingValueCard(title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 38, height: 38)
                .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))

            Text(title.localizedKey)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail.localizedKey)
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PayGuardPremiumCardBackground(cornerRadius: 24))
    }

    private func onboardingCheckRow(title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))
            Text(title.localizedKey)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var buttonTitleForNotifications: String {
        switch notificationState.status {
        case .authorized, .provisional, .ephemeral:
            PMLocalized("Notifications are ready")
        case .denied:
            PMLocalized("Notifications were denied")
        default:
            PMLocalized("Allow notifications")
        }
    }

    private var permissionSummary: String {
        switch notificationState.status {
        case .authorized, .provisional, .ephemeral:
            PMLocalized("Allowed")
        case .denied:
            PMLocalized("Denied")
        default:
            PMLocalized("Not requested")
        }
    }

    private func continueFlow() {
        if step < Self.totalSteps - 1 {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                step += 1
            }
        } else {
            onComplete(includeSampleData)
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title.localizedKey)
                .foregroundStyle(PayGuardTheme.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(PayGuardTheme.textPrimary)
        }
        .font(.system(.subheadline, design: .rounded))
    }
}

private struct OnboardingEmailSourceCard: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))

            Text(title.localizedKey)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PayGuardPremiumCardBackground(cornerRadius: 24))
    }
}

private struct PremiumCurrencyPicker: View {
    @Binding var selection: String
    @State private var searchText = ""

    private let currencies: [CurrencyOption] = [
        CurrencyOption(code: "EUR", symbol: "€", title: "Euro", accent: [PayGuardTheme.ocean, PayGuardTheme.seafoam]),
        CurrencyOption(code: "USD", symbol: "$", title: "US Dollar", accent: [PayGuardTheme.ocean.opacity(0.92), PayGuardTheme.accent]),
        CurrencyOption(code: "TRY", symbol: "₺", title: "Turkish Lira", accent: [PayGuardTheme.accent, PayGuardTheme.seafoam.opacity(0.92)]),
        CurrencyOption(code: "GBP", symbol: "£", title: "British Pound", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.ocean.opacity(0.86)]),
        CurrencyOption(code: "CHF", symbol: "CHF", title: "Swiss Franc", accent: [PayGuardTheme.ocean, PayGuardTheme.accent.opacity(0.86)]),
        CurrencyOption(code: "CAD", symbol: "$", title: "Canadian Dollar", accent: [PayGuardTheme.ocean.opacity(0.82), PayGuardTheme.seafoam]),
        CurrencyOption(code: "AUD", symbol: "$", title: "Australian Dollar", accent: [PayGuardTheme.accent.opacity(0.82), PayGuardTheme.ocean]),
        CurrencyOption(code: "NZD", symbol: "$", title: "New Zealand Dollar", accent: [PayGuardTheme.seafoam.opacity(0.86), PayGuardTheme.ocean]),
        CurrencyOption(code: "JPY", symbol: "¥", title: "Japanese Yen", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.accent]),
        CurrencyOption(code: "CNY", symbol: "¥", title: "Chinese Yuan", accent: [PayGuardTheme.accent, PayGuardTheme.ocean.opacity(0.80)]),
        CurrencyOption(code: "HKD", symbol: "$", title: "Hong Kong Dollar", accent: [PayGuardTheme.ocean, PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "SGD", symbol: "$", title: "Singapore Dollar", accent: [PayGuardTheme.seafoam, PayGuardTheme.ocean]),
        CurrencyOption(code: "SEK", symbol: "kr", title: "Swedish Krona", accent: [PayGuardTheme.ocean.opacity(0.90), PayGuardTheme.accent.opacity(0.72)]),
        CurrencyOption(code: "NOK", symbol: "kr", title: "Norwegian Krone", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.seafoam.opacity(0.76)]),
        CurrencyOption(code: "DKK", symbol: "kr", title: "Danish Krone", accent: [PayGuardTheme.accent.opacity(0.84), PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "PLN", symbol: "zł", title: "Polish Zloty", accent: [PayGuardTheme.ocean, PayGuardTheme.accent.opacity(0.72)]),
        CurrencyOption(code: "CZK", symbol: "Kč", title: "Czech Koruna", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.ocean]),
        CurrencyOption(code: "HUF", symbol: "Ft", title: "Hungarian Forint", accent: [PayGuardTheme.accent, PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "RON", symbol: "lei", title: "Romanian Leu", accent: [PayGuardTheme.ocean.opacity(0.84), PayGuardTheme.seafoam.opacity(0.90)]),
        CurrencyOption(code: "BGN", symbol: "лв", title: "Bulgarian Lev", accent: [PayGuardTheme.seafoam, PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "HRK", symbol: "kn", title: "Croatian Kuna", accent: [PayGuardTheme.ocean, PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "RSD", symbol: "дин", title: "Serbian Dinar", accent: [PayGuardTheme.accent.opacity(0.72), PayGuardTheme.ocean]),
        CurrencyOption(code: "UAH", symbol: "₴", title: "Ukrainian Hryvnia", accent: [PayGuardTheme.ocean.opacity(0.88), PayGuardTheme.seafoam]),
        CurrencyOption(code: "ILS", symbol: "₪", title: "Israeli Shekel", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.accent.opacity(0.82)]),
        CurrencyOption(code: "AED", symbol: "د.إ", title: "UAE Dirham", accent: [PayGuardTheme.ocean, PayGuardTheme.seafoam.opacity(0.82)]),
        CurrencyOption(code: "SAR", symbol: "﷼", title: "Saudi Riyal", accent: [PayGuardTheme.seafoam, PayGuardTheme.ocean.opacity(0.84)]),
        CurrencyOption(code: "QAR", symbol: "ر.ق", title: "Qatari Riyal", accent: [PayGuardTheme.accent.opacity(0.78), PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "KWD", symbol: "د.ك", title: "Kuwaiti Dinar", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.seafoam]),
        CurrencyOption(code: "INR", symbol: "₹", title: "Indian Rupee", accent: [PayGuardTheme.accent, PayGuardTheme.seafoam]),
        CurrencyOption(code: "PKR", symbol: "₨", title: "Pakistani Rupee", accent: [PayGuardTheme.seafoam.opacity(0.84), PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "THB", symbol: "฿", title: "Thai Baht", accent: [PayGuardTheme.ocean, PayGuardTheme.accent.opacity(0.80)]),
        CurrencyOption(code: "MYR", symbol: "RM", title: "Malaysian Ringgit", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.ocean.opacity(0.82)]),
        CurrencyOption(code: "IDR", symbol: "Rp", title: "Indonesian Rupiah", accent: [PayGuardTheme.accent.opacity(0.82), PayGuardTheme.seafoam]),
        CurrencyOption(code: "PHP", symbol: "₱", title: "Philippine Peso", accent: [PayGuardTheme.ocean.opacity(0.84), PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "KRW", symbol: "₩", title: "South Korean Won", accent: [PayGuardTheme.accent.opacity(0.78), PayGuardTheme.ocean]),
        CurrencyOption(code: "ZAR", symbol: "R", title: "South African Rand", accent: [PayGuardTheme.seafoam, PayGuardTheme.ocean.opacity(0.82)]),
        CurrencyOption(code: "EGP", symbol: "E£", title: "Egyptian Pound", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.accent.opacity(0.74)]),
        CurrencyOption(code: "MAD", symbol: "DH", title: "Moroccan Dirham", accent: [PayGuardTheme.accent.opacity(0.76), PayGuardTheme.seafoam]),
        CurrencyOption(code: "BRL", symbol: "R$", title: "Brazilian Real", accent: [PayGuardTheme.seafoam, PayGuardTheme.accent.opacity(0.86)]),
        CurrencyOption(code: "MXN", symbol: "$", title: "Mexican Peso", accent: [PayGuardTheme.ocean, PayGuardTheme.seafoam.opacity(0.86)]),
        CurrencyOption(code: "ARS", symbol: "$", title: "Argentine Peso", accent: [PayGuardTheme.accent.opacity(0.72), PayGuardTheme.ocean.opacity(0.88)]),
        CurrencyOption(code: "CLP", symbol: "$", title: "Chilean Peso", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.ocean.opacity(0.84)]),
        CurrencyOption(code: "COP", symbol: "$", title: "Colombian Peso", accent: [PayGuardTheme.seafoam.opacity(0.78), PayGuardTheme.accent]),
        CurrencyOption(code: "PEN", symbol: "S/", title: "Peruvian Sol", accent: [PayGuardTheme.ocean.opacity(0.80), PayGuardTheme.surfaceStrong]),
        CurrencyOption(code: "RUB", symbol: "₽", title: "Russian Ruble", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.accent.opacity(0.78)]),
        CurrencyOption(code: "ISK", symbol: "kr", title: "Icelandic Krona", accent: [PayGuardTheme.ocean, PayGuardTheme.seafoam.opacity(0.80)]),
        CurrencyOption(code: "GEL", symbol: "₾", title: "Georgian Lari", accent: [PayGuardTheme.accent.opacity(0.80), PayGuardTheme.ocean.opacity(0.78)]),
        CurrencyOption(code: "ALL", symbol: "L", title: "Albanian Lek", accent: [PayGuardTheme.surfaceStrong, PayGuardTheme.seafoam.opacity(0.82)]),
        CurrencyOption(code: "BAM", symbol: "KM", title: "Bosnia Convertible Mark", accent: [PayGuardTheme.ocean.opacity(0.82), PayGuardTheme.accent.opacity(0.76)]),
        CurrencyOption(code: "MKD", symbol: "ден", title: "Macedonian Denar", accent: [PayGuardTheme.accent.opacity(0.78), PayGuardTheme.surfaceStrong])
    ]


    private let featuredCodes = ["EUR", "USD", "TRY", "GBP", "CHF", "CAD", "AUD", "JPY"]
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var currentSelection: CurrencyOption {
        currencies.first(where: { $0.code == selection }) ?? currencies[0]
    }

    private var featuredCurrencies: [CurrencyOption] {
        featuredCodes.compactMap { code in currencies.first(where: { $0.code == code }) }
    }

    private var filteredCurrencies: [CurrencyOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return currencies }
        return currencies.filter { option in
            option.code.localizedCaseInsensitiveContains(query) ||
            option.title.localizedCaseInsensitiveContains(query) ||
            option.symbol.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            currencySearchField

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("All supported currencies".localizedKey)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(PayGuardTheme.accent)
                            .tracking(0.8)
                        Text("Choose the default used for totals, imports and new records.".localizedKey)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(PayGuardTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Text("\(filteredCurrencies.count)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PayGuardTheme.accent.opacity(0.12), in: Capsule())
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredCurrencies) { currency in
                        Button {
                            select(currency)
                        } label: {
                            CompactCurrencyCard(
                                option: currency,
                                isSelected: selection == currency.code
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(PayGuardPremiumCardBackground(cornerRadius: 28))
        }
    }

    private var selectedCurrencyHero: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: currentSelection.accent,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: PayGuardTheme.accent.opacity(0.20), radius: 18, x: 0, y: 12)

                Text(currentSelection.symbol)
                    .font(.system(size: currentSelection.symbol.count > 2 ? 22 : 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Default currency".localizedKey)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(PayGuardTheme.accent)
                    .tracking(0.8)
                Text(currentSelection.title.localizedKey)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(currentSelection.code) · Used for dashboard totals and new entries".localizedKey)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [PayGuardTheme.surfaceStrong.opacity(0.98), PayGuardTheme.surface.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(PayGuardTheme.accent.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 22, x: 0, y: 14)
    }

    private var currencySearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PayGuardTheme.textSecondary)

            TextField("Search currency or code".localizedKey, text: $searchText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(PayGuardTheme.textSecondary.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(
            PayGuardTheme.surfaceSecondary.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func select(_ currency: CurrencyOption) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selection = currency.code
        }
    }
}

private struct CurrencyOption: Identifiable {
    let code: String
    let symbol: String
    let title: String
    let accent: [Color]

    var id: String { code }
}

private struct FeaturedCurrencyTile: View {
    let option: CurrencyOption
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(option.symbol)
                    .font(.system(size: option.symbol.count > 2 ? 16 : 24, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? .white : PayGuardTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .frame(width: 44, height: 44)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? .white : PayGuardTheme.textSecondary.opacity(0.70))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(option.code)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? .white : PayGuardTheme.textPrimary)
                Text(option.title.localizedKey)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.84) : PayGuardTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 134, alignment: .topLeading)
        .padding(14)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isSelected ? .white.opacity(0.24) : PayGuardTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: isSelected ? PayGuardTheme.accent.opacity(0.18) : .clear, radius: 16, x: 0, y: 10)
    }

    private var background: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(LinearGradient(colors: option.accent, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(LinearGradient(colors: [PayGuardTheme.surfaceSecondary.opacity(0.96), PayGuardTheme.surface.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var iconBackground: some ShapeStyle {
        if isSelected { return AnyShapeStyle(.white.opacity(0.16)) }
        return AnyShapeStyle(PayGuardTheme.accent.opacity(0.10))
    }
}

private struct CompactCurrencyCard: View {
    let option: CurrencyOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(option.symbol)
                .font(.system(size: option.symbol.count > 2 ? 11 : 17, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? .white : PayGuardTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(width: 36, height: 36)
                .background(symbolBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(option.code)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? .white : PayGuardTheme.textPrimary)
                Text(option.title.localizedKey)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : PayGuardTheme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(12)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? .white.opacity(0.24) : PayGuardTheme.stroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(LinearGradient(colors: option.accent, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(PayGuardTheme.surfaceSecondary.opacity(0.72))
    }

    private var symbolBackground: some ShapeStyle {
        if isSelected { return AnyShapeStyle(.white.opacity(0.16)) }
        return AnyShapeStyle(PayGuardTheme.accent.opacity(0.11))
    }
}

private struct TrackingScopeOptionCard: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isOn ? [PayGuardTheme.ocean, PayGuardTheme.accent] : [PayGuardTheme.surfaceSecondary, PayGuardTheme.inputFill],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(isOn ? .white : PayGuardTheme.accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title.localizedKey)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(detail.localizedKey)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(PayGuardTheme.accent)
        }
        .padding(16)
        .background(PayGuardPremiumCardBackground(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(isOn ? PayGuardTheme.accent.opacity(0.24) : PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}

private struct ToggleCard: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.localizedKey)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(detail.localizedKey)
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
        }
        .tint(PayGuardTheme.accent)
        .padding(18)
        .payGuardCardStyle()
    }
}

private struct OnboardingWidgetShowcase: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 14) {
                premiumMediumWidget

                HStack(spacing: 12) {
                    premiumSmallWidget(
                        title: "Next charge",
                        value: "€12.99",
                        detail: PMLocalized("Netflix · 3d"),
                        symbol: "bolt.horizontal.circle.fill"
                    )
                    premiumSmallWidget(
                        title: "Return",
                        value: PMLocalized("7 days"),
                        detail: "AirPods Pro",
                        symbol: "arrow.uturn.backward.circle.fill"
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                PayGuardTheme.surfaceStrong.opacity(0.96),
                                PayGuardTheme.surface.opacity(0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 16)
        }
    }

    private var premiumMediumWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("PayGuard", systemImage: "square.grid.2x2.fill")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Text("PRO")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
            }

            Text("Monthly overview")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Text("€48.40")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                widgetPill(title: "4 active", symbol: "checkmark.circle.fill")
                widgetPill(title: "1 review", symbol: "exclamationmark.circle.fill")
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next charge")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("Spotify · Tomorrow")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [PayGuardTheme.ocean.opacity(0.98), PayGuardTheme.accent.opacity(0.94), PayGuardTheme.seafoam.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: PayGuardTheme.accent.opacity(0.22), radius: 24, x: 0, y: 16)
    }

    private func premiumSmallWidget(title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PayGuardTheme.accent)
                Spacer()
                Circle()
                    .stroke(.white.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
            }

            Text(title.localizedKey)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PayGuardTheme.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PayGuardTheme.textPrimary)
            Text(detail)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PayGuardTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PayGuardTheme.surfaceStrong.opacity(0.98),
                            PayGuardTheme.surfaceSecondary.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 14)
    }

    private func widgetPill(title: String, symbol: String) -> some View {
        Label(title.localizedKey, systemImage: symbol)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.14), in: Capsule())
    }
}
