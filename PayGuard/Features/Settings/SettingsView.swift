//
//  SettingsView.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    private static let siteRootURL = URL(string: "https://aozkul.github.io/PayGuard/")!
    private static let privacyPolicyURL = URL(string: "https://aozkul.github.io/PayGuard/privacy")!
    private static let supportURL = URL(string: "https://aozkul.github.io/PayGuard/support")!
    private static let termsURL = URL(string: "https://aozkul.github.io/PayGuard/terms")!
    private static let contactEmailURL = URL(string: "mailto:ali.ozkul@icloud.com")!

    @Environment(PremiumAccessController.self) private var premiumAccess
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.modelContext) private var modelContext
    @Query private var subscriptions: [SubscriptionRecord]
    @Query private var purchases: [PurchaseRightItem]
    @Query private var members: [FamilyMember]
    @Query(sort: \ConnectedEmailAccount.updatedAt, order: .reverse) private var connectedEmailAccounts: [ConnectedEmailAccount]

    @StateObject private var notificationState = NotificationPermissionState()
    @State private var premiumGate: PremiumGate?
    @State private var showingDeleteAllConfirmation = false
    @State private var deleteAllStatusMessage: String?
    @State private var isDeletingAllData = false
    @State private var showingEmailAccountSetup = false
    @State private var emailAccountIDPendingDeletion: UUID?
    @State private var mailboxPickerAccountID: UUID?
    @State private var expandedPanels: Set<SettingsPanelID> = []

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("prefersSampleData") private var prefersSampleData = false
    @AppStorage("selectedThemePreference") private var selectedThemeRaw = ThemePreference.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var selectedLanguageRaw = AppLanguage.fallback.rawValue

    private var householdSnapshot: DashboardSnapshot {
        BillingEngine.shared.snapshot(subscriptions: subscriptions, purchases: purchases, members: members)
    }

    private var activeSubscriptionCount: Int {
        subscriptions.filter { !$0.isArchived }.count
    }

    private var activePurchaseCount: Int {
        purchases.filter { !$0.isArchived }.count
    }

    private var appVersionLabel: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(buildNumber))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    premiumSettingsHero
                        .padding(.top, 8)
                    settingsCluster(
                        title: "Automation",
                        subtitle: "Email accounts and privacy controls."
                    ) {
                        emailAccountsPanel
                        privacyPanel
                    }

                    settingsCluster(
                        title: "Experience",
                        subtitle: "Theme, language, family, and widgets."
                    ) {
                        appearancePanel
                        familyPanel
                        widgetPanel
                    }

                    settingsCluster(
                        title: "App and data",
                        subtitle: "Pro status, support, defaults, and reset tools."
                    ) {
                        proPanel
                        aboutPanel
                        defaultsPanel
                        dangerPanel
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(PayGuardBackdrop())
            .navigationTitle("Settings")
            .payGuardNavigationChrome()
            .task {
                premiumAccess.start()
                await premiumAccess.loadProductsIfNeeded()
                await notificationState.refresh()
            }
            .sheet(isPresented: $showingEmailAccountSetup) {
                EmailAccountSetupView()
            }
            .sheet(
                isPresented: Binding(
                    get: { mailboxPickerAccountID != nil },
                    set: { if !$0 { mailboxPickerAccountID = nil } }
                )
            ) {
                if let mailboxPickerAccount {
                    EmailMailboxPickerView(account: mailboxPickerAccount)
                }
            }
            .sheet(item: $premiumGate) { gate in
                PremiumUpgradeSheet(gate: gate)
            }
            .confirmationDialog(
                "Delete email account?",
                isPresented: Binding(
                    get: { emailAccountIDPendingDeletion != nil },
                    set: { if !$0 { emailAccountIDPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    deletePendingEmailAccount()
                }
                Button("Cancel", role: .cancel) {
                    emailAccountIDPendingDeletion = nil
                }
            } message: {
                Text("PayGuard removes the mailbox connection and deletes the saved password from Keychain. Existing subscription records are not deleted.")
            }
            .confirmationDialog(
                "Delete all local data?",
                isPresented: $showingDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    deleteAllLocalData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes subscriptions, protected purchases, household members, connected email accounts, and their local reminders from this device.")
            }
            .alert(
                "Local data deleted",
                isPresented: Binding(
                    get: { deleteAllStatusMessage != nil },
                    set: { if !$0 { deleteAllStatusMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAllStatusMessage ?? "")
            }
            .onAppear {
                handleSettingsDeepLink()
            }
            .onChange(of: appRouter.settingsTarget) { _, _ in
                handleSettingsDeepLink()
            }
        }
    }

    private var premiumSettingsHero: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [PayGuardTheme.ocean.opacity(0.95), PayGuardTheme.accent.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .shadow(color: PayGuardTheme.accent.opacity(0.20), radius: 16, x: 0, y: 10)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("SETTINGS")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(PayGuardTheme.accent)
                    .tracking(0.8)
                Text("Control center")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text("Open only what you need. Email accounts, privacy, appearance, and data tools stay grouped below.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                PayGuardTag(title: premiumAccess.isLifetimeUnlocked ? "PRO" : "FREE")
                Text("v\(appVersionLabel)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
        }
        .padding(16)
        .background(PayGuardPremiumCardBackground(cornerRadius: 28))
    }

    private func settingsCluster<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.localizedKey)
                        .font(.system(.title3, design: .rounded, weight: .heavy))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    Text(subtitle.localizedKey)
                        .font(PayGuardTheme.captionFont)
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 10) {
                content()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(PayGuardTheme.surface.opacity(0.50))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(PayGuardTheme.stroke.opacity(0.75), lineWidth: 1)
            }
        }
    }

    private var proPanel: some View {
        SettingsAccordionPanel(
            title: premiumAccess.isLifetimeUnlocked ? "Lifetime Pro" : "PayGuard Pro",
            symbol: premiumAccess.isLifetimeUnlocked ? "checkmark.seal.fill" : "sparkles.rectangle.stack.fill",
            detail: premiumAccess.isLifetimeUnlocked
                ? "The full PayGuard toolkit is unlocked on this device."
                : "Unlock unlimited records, smart import, email discovery, family management, premium widgets, and advanced summaries.",
            isExpanded: expansionBinding(.pro)
        ) {
            PayGuardMetricBadge(title: "Price", value: premiumAccess.lifetimePriceLabel)

            if !premiumAccess.isLifetimeUnlocked {
                Button("View Pro unlock") {
                    premiumGate = .advancedSummaries
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }

            Button("Restore Purchases") {
                Task { _ = await premiumAccess.restorePurchases() }
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
    }

    private var emailAccountsPanel: some View {
        SettingsAccordionPanel(
            title: "Email accounts",
            symbol: "envelope.badge.shield.half.filled",
            detail: connectedEmailAccounts.isEmpty
                ? "Connect a mailbox for automatic subscription discovery."
                : "Manage the connected mailboxes used for automatic subscription discovery.",
            isExpanded: expansionBinding(.emailAccounts)
        ) {
            if connectedEmailAccounts.isEmpty {
                emailInfoRow(
                    title: "No mailbox connected",
                    detail: "Add an email account here. The Subscriptions screen only runs the scan; account setup stays in Settings."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(connectedEmailAccounts) { account in
                        connectedEmailAccountRow(account)
                    }
                }
            }

            Button {
                showingEmailAccountSetup = true
            } label: {
                Label("Add email account", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    private func connectedEmailAccountRow(_ account: ConnectedEmailAccount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: account.provider.symbolName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(PayGuardTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    Text(account.emailAddress)
                        .font(PayGuardTheme.captionFont)
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .lineLimit(2)
                    Text(account.lastScanStatus.localizedKey)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary.opacity(0.85))
                        .lineLimit(2)
                }

                Spacer()

                Button(role: .destructive) {
                    emailAccountIDPendingDeletion = account.id
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(PayGuardTheme.destructive)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(PayGuardTheme.destructive.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete email account")
            }

            Button {
                mailboxPickerAccountID = account.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scan mailbox")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textSecondary)
                        Text(account.selectedScanMailbox)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PayGuardTheme.inputFill))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PayGuardTheme.stroke, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PayGuardTheme.surfaceSecondary))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private var mailboxPickerAccount: ConnectedEmailAccount? {
        guard let mailboxPickerAccountID else { return nil }
        return connectedEmailAccounts.first(where: { $0.id == mailboxPickerAccountID })
    }

    private var appearancePanel: some View {
        SettingsAccordionPanel(
            title: "Appearance",
            symbol: "swatchpalette",
            detail: "Theme and language changes update the whole app immediately.",
            isExpanded: expansionBinding(.appearance)
        ) {
            Picker("Theme", selection: $selectedThemeRaw) {
                ForEach(ThemePreference.allCases) { theme in
                    Text(theme.title).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("System follows the device, while Light and Dark lock in a curated PayGuard presentation.")
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)

            PremiumLanguagePicker(
                title: "App language",
                detail: "Choose the language used across the app.",
                selection: Binding(
                    get: { AppLanguage(rawValue: selectedLanguageRaw) ?? .fallback },
                    set: { selectedLanguageRaw = $0.rawValue }
                )
            )
        }
    }

    private var privacyPanel: some View {
        SettingsAccordionPanel(
            title: "Privacy and permissions",
            symbol: "lock.shield.fill",
            detail: "Notifications stay local. Email credentials are kept in Keychain and suggestions require approval.",
            isExpanded: expansionBinding(.privacy)
        ) {
            PayGuardKeyValueRow(title: "Notification status", value: notificationLabel)

            Button(notificationActionTitle) {
                handleNotificationAction()
            }
            .buttonStyle(PrimaryActionButtonStyle())

            VStack(alignment: .leading, spacing: 10) {
                notificationInfoRow(
                    title: "Billing reminders",
                    detail: "Subscription renewals can alert you 7, 3, and 1 day before the next charge."
                )
                notificationInfoRow(
                    title: "Email auto scan privacy",
                    detail: "Only the mailboxes connected in Settings are scanned. Detected subscriptions are shown as suggestions before saving."
                )
                notificationInfoRow(
                    title: "Return window alerts",
                    detail: "Protected purchases can remind you before the return period closes."
                )
                notificationInfoRow(
                    title: "Warranty ending alerts",
                    detail: "Longer coverage reminders can fire 30 and 7 days before expiry."
                )
            }
        }
    }

    private var familyPanel: some View {
        SettingsAccordionPanel(
            title: "Family and household",
            symbol: "person.3.sequence.fill",
            detail: "Manage owners, payers, and shared totals without taking over the main navigation.",
            isExpanded: expansionBinding(.family)
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PayGuardMetricBadge(title: "Members", value: "\(members.count)")
                PayGuardMetricBadge(title: "Monthly", value: householdSnapshot.monthlyTotal.currencyString(code: "EUR"))
                PayGuardMetricBadge(title: "Subscriptions", value: "\(activeSubscriptionCount)")
                PayGuardMetricBadge(title: "Protected", value: "\(activePurchaseCount)")
            }

            if premiumAccess.canUseFamilyManagement() {
                NavigationLink {
                    FamilyView()
                } label: {
                    PayGuardNavigationRow(
                        title: "Open family setup",
                        detail: "Manage people, roles, and shared cost visibility.",
                        value: members.isEmpty ? "Start" : "\(members.count) saved"
                    )
                }
                .buttonStyle(.plain)
            } else {
                PremiumLockedCard(
                    title: "Family management",
                    detail: "Owners, payers, and household members are part of Lifetime Pro.",
                    buttonTitle: "Unlock Pro"
                ) {
                    premiumGate = .familyManagement
                }
            }
        }
    }

    private var widgetPanel: some View {
        SettingsAccordionPanel(
            title: "Premium widgets",
            symbol: "square.grid.2x2.fill",
            detail: "Home Screen widgets show monthly totals, next charges, and review priorities.",
            isExpanded: expansionBinding(.widgets)
        ) {
            if premiumAccess.canUsePremiumWidgets() {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    PayGuardMetricBadge(title: "Two widgets", value: "Overview + Focus")
                    PayGuardMetricBadge(title: "Sizes", value: "Small + Medium")
                }
                widgetInfoRow(title: "Overview widget", detail: "Monthly total, active plans, and next charge at a glance.")
                widgetInfoRow(title: "Focus widget", detail: "Top priority, review count, and protected purchase coverage.")
                widgetInfoRow(title: "Add from Home Screen", detail: "Long-press the Home Screen, tap Edit, and add PayGuard widgets.")
            } else {
                PremiumLockedCard(
                    title: "Premium widgets",
                    detail: "Home Screen widgets are part of Lifetime Pro.",
                    buttonTitle: "Unlock Pro"
                ) {
                    premiumGate = .premiumWidgets
                }
            }
        }
    }

    private var aboutPanel: some View {
        SettingsAccordionPanel(
            title: "About and privacy links",
            symbol: "hand.raised.fill",
            detail: "Version, support, website, policy, and terms in one compact panel.",
            isExpanded: expansionBinding(.about)
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PayGuardMetricBadge(title: "Version", value: appVersionLabel)
                PayGuardMetricBadge(title: "Account", value: connectedEmailAccounts.isEmpty ? "Not required" : "Email optional")
            }

            Link(destination: Self.privacyPolicyURL) {
                PayGuardNavigationRow(title: "Privacy Policy", detail: "Read how PayGuard stores data, handles on-device processing, and supports deletion.", value: "Open")
            }
            .buttonStyle(.plain)

            Link(destination: Self.supportURL) {
                PayGuardNavigationRow(title: "Support", detail: "Open the support page for help with purchases, widgets, reminders, or imports.", value: "Open")
            }
            .buttonStyle(.plain)

            Link(destination: Self.termsURL) {
                PayGuardNavigationRow(title: "Terms of Use", detail: "Review the terms that apply to using PayGuard and its premium features.", value: "Open")
            }
            .buttonStyle(.plain)

            Link(destination: Self.contactEmailURL) {
                PayGuardNavigationRow(title: "Contact email", detail: "Reach the developer directly by email for support or review follow-up.", value: "ali.ozkul@icloud.com")
            }
            .buttonStyle(.plain)

            Link(destination: Self.siteRootURL) {
                PayGuardNavigationRow(title: "Website", detail: "Open the public PayGuard page hosted on GitHub Pages.", value: "Open")
            }
            .buttonStyle(.plain)
        }
    }

    private var defaultsPanel: some View {
        SettingsAccordionPanel(
            title: "Defaults",
            symbol: "slider.horizontal.3",
            detail: "Useful for demos, walkthroughs, and quick environment resets.",
            isExpanded: expansionBinding(.defaults)
        ) {
            Toggle("Keep sample data for demos", isOn: $prefersSampleData)
                .tint(PayGuardTheme.accent)

            Button("Replay onboarding") {
                hasCompletedOnboarding = false
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
    }

    private var dangerPanel: some View {
        SettingsAccordionPanel(
            title: "Danger zone",
            symbol: "exclamationmark.triangle.fill",
            detail: "Delete local PayGuard records and connected mailbox credentials from this device.",
            isExpanded: expansionBinding(.danger)
        ) {
            Button(role: .destructive) {
                showingDeleteAllConfirmation = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text(isDeletingAllData ? "Deleting..." : "Delete all local data")
                }
            }
            .buttonStyle(DestructiveActionButtonStyle())
            .disabled(isDeletingAllData)
        }
    }

    private var notificationActionTitle: String {
        switch notificationState.status {
        case .denied:
            PMLocalized("Open iPhone Settings")
        case .authorized, .provisional, .ephemeral:
            PMLocalized("Review notification settings")
        default:
            PMLocalized("Enable notifications")
        }
    }

    private var notificationLabel: String {
        switch notificationState.status {
        case .authorized, .provisional, .ephemeral:
            PMLocalized("Allowed")
        case .denied:
            PMLocalized("Denied")
        default:
            PMLocalized("Not requested")
        }
    }

    private func expansionBinding(_ panel: SettingsPanelID) -> Binding<Bool> {
        Binding(
            get: { expandedPanels.contains(panel) },
            set: { isExpanded in
                if isExpanded {
                    expandedPanels.insert(panel)
                } else {
                    expandedPanels.remove(panel)
                }
            }
        )
    }

    private func handleNotificationAction() {
        Task {
            switch notificationState.status {
            case .notDetermined:
                _ = await NotificationScheduler.shared.requestPermission()
                await notificationState.refresh()
            case .denied, .authorized, .provisional, .ephemeral:
                NotificationScheduler.shared.openSystemSettings()
            @unknown default:
                await notificationState.refresh()
            }
        }
    }

    private func deletePendingEmailAccount() {
        guard let pendingID = emailAccountIDPendingDeletion,
              let account = connectedEmailAccounts.first(where: { $0.id == pendingID }) else {
            emailAccountIDPendingDeletion = nil
            return
        }
        EmailCredentialStore.deletePassword(for: account.passwordKeychainKey)
        modelContext.delete(account)
        try? modelContext.save()
        emailAccountIDPendingDeletion = nil
    }

    private func deleteAllLocalData() {
        isDeletingAllData = true

        subscriptions.forEach(modelContext.delete)
        purchases.forEach(modelContext.delete)
        members.forEach(modelContext.delete)
        connectedEmailAccounts.forEach { account in
            EmailCredentialStore.deletePassword(for: account.passwordKeychainKey)
            modelContext.delete(account)
        }

        do {
            try modelContext.save()
        } catch {
            deleteAllStatusMessage = PMLocalized("We couldn't delete everything. Please try again.")
            isDeletingAllData = false
            return
        }

        NotificationScheduler.shared.removeAllPendingNotifications()
        premiumAccess.resetLocalUsageState()
        deleteAllStatusMessage = PMLocalized("Your saved subscriptions, purchases, household members, connected email accounts, and pending reminders were removed from this device.")
        isDeletingAllData = false
    }

    private func notificationInfoRow(title: String, detail: String) -> some View {
        infoRow(title: title, detail: detail, tagTitle: "Local")
    }

    private func widgetInfoRow(title: String, detail: String) -> some View {
        infoRow(title: title, detail: detail, tagTitle: nil)
    }

    private func emailInfoRow(title: String, detail: String) -> some View {
        infoRow(title: title, detail: detail, tagTitle: "Email")
    }

    private func infoRow(title: String, detail: String, tagTitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.localizedKey)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Spacer()
                if let tagTitle {
                    PayGuardTag(title: tagTitle)
                }
            }

            Text(detail.localizedKey)
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PayGuardTheme.surfaceSecondary))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func handleSettingsDeepLink() {
        guard let target = appRouter.settingsTarget else { return }

        switch target {
        case .emailAccounts:
            expandedPanels.insert(.emailAccounts)
        }

        appRouter.settingsTarget = nil
    }
}

private enum SettingsPanelID: Hashable {
    case pro
    case emailAccounts
    case appearance
    case privacy
    case family
    case widgets
    case about
    case defaults
    case danger
}

private struct SettingsAccordionPanel<Content: View>: View {
    let title: String
    let symbol: String
    let detail: String
    @Binding var isExpanded: Bool
    let content: () -> Content

    init(
        title: String,
        symbol: String,
        detail: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(PayGuardTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(PayGuardTheme.accent.opacity(0.14)))
                        .overlay {
                            Circle().stroke(PayGuardTheme.accent.opacity(0.22), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.localizedKey)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                        Text(detail.localizedKey)
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)
                            .lineLimit(isExpanded ? 3 : 2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(PayGuardTheme.surfaceSecondary))
                        .overlay {
                            Circle().stroke(PayGuardTheme.stroke, lineWidth: 1)
                        }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.top, 14)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PayGuardTheme.surface,
                            PayGuardTheme.surfaceSecondary.opacity(0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: PayGuardTheme.shadow.opacity(isExpanded ? 1 : 0.55), radius: isExpanded ? 18 : 8, x: 0, y: isExpanded ? 10 : 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isExpanded ? PayGuardTheme.accent.opacity(0.28) : PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}

private struct EmailMailboxPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let account: ConnectedEmailAccount

    @State private var availableMailboxes: [String] = []
    @State private var selectedMailbox: String
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(account: ConnectedEmailAccount) {
        self.account = account
        _selectedMailbox = State(initialValue: account.selectedScanMailbox)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PayGuardBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitleView(
                            eyebrow: "Scan Mailbox",
                            title: "Choose one mailbox for faster email scans.",
                            detail: "PayGuard scans only this folder for the selected account. INBOX stays the safe default, but you can switch to a dedicated billing or receipts folder."
                        )

                        PayGuardPanel(
                            title: account.displayName,
                            symbol: account.provider.symbolName,
                            detail: account.emailAddress
                        ) {
                            if isLoading {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    Text("Loading mailboxes…".localizedKey)
                                        .font(PayGuardTheme.captionFont)
                                        .foregroundStyle(PayGuardTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else if let errorMessage {
                                Text(errorMessage)
                                    .font(PayGuardTheme.captionFont)
                                    .foregroundStyle(PayGuardTheme.destructive)
                            } else {
                                ForEach(availableMailboxes, id: \.self) { mailbox in
                                    Button {
                                        selectedMailbox = mailbox
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(mailbox)
                                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                                    .foregroundStyle(PayGuardTheme.textPrimary)
                                                if mailbox.caseInsensitiveCompare("INBOX") == .orderedSame {
                                                    Text("Best default for the fastest and safest scan coverage.")
                                                        .font(PayGuardTheme.captionFont)
                                                        .foregroundStyle(PayGuardTheme.textSecondary)
                                                }
                                            }

                                            Spacer()

                                            Image(systemName: selectedMailbox.caseInsensitiveCompare(mailbox) == .orderedSame ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundStyle(selectedMailbox.caseInsensitiveCompare(mailbox) == .orderedSame ? PayGuardTheme.accent : PayGuardTheme.textSecondary)
                                        }
                                        .padding(14)
                                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PayGuardTheme.inputFill))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(selectedMailbox.caseInsensitiveCompare(mailbox) == .orderedSame ? PayGuardTheme.accent.opacity(0.45) : PayGuardTheme.stroke, lineWidth: 1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button("Save mailbox selection") {
                            saveSelection()
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(isLoading || availableMailboxes.isEmpty)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Scan Mailbox")
            .navigationBarTitleDisplayMode(.inline)
            .payGuardNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        ToolbarCircleIcon(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .task {
                await loadMailboxes()
            }
        }
    }

    private func loadMailboxes() async {
        isLoading = true
        errorMessage = nil

        do {
            let mailboxes = try await EmailAutoDiscoveryService.shared.availableMailboxes(
                account: EmailAccountConnectionSnapshot(account: account)
            )
            await MainActor.run {
                availableMailboxes = mailboxes
                if !mailboxes.contains(where: { $0.caseInsensitiveCompare(selectedMailbox) == .orderedSame }),
                   let inbox = mailboxes.first(where: { $0.caseInsensitiveCompare("INBOX") == .orderedSame }) {
                    selectedMailbox = inbox
                } else if selectedMailbox.isEmpty, let first = mailboxes.first {
                    selectedMailbox = first
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func saveSelection() {
        account.selectedScanMailbox = selectedMailbox
        account.updatedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
