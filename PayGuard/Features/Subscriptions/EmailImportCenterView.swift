//
//  EmailImportCenterView.swift
//  PayGuard
//
//  Automatic email account based subscription discovery.
//

import SwiftData
import SwiftUI

struct EmailImportCenterView: View {
    @Environment(AppRouter.self) private var appRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PremiumAccessController.self) private var premiumAccess
    @Query(sort: \ConnectedEmailAccount.updatedAt, order: .reverse) private var accounts: [ConnectedEmailAccount]

    let templates: [ServiceTemplate]
    let onDraftReady: (SubscriptionImportDraft) -> Void

    @State private var scanState: EmailScanState = .idle
    @State private var findings: [EmailScanFinding] = []
    @State private var liveFindings: [EmailScanFinding] = []
    @State private var liveFindingCount = 0
    @State private var statusMessage: String?
    @State private var showingScanExperience = false
    @State private var showingResults = false

    var body: some View {
        NavigationStack {
            ZStack {
                PayGuardBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionTitleView(
                            eyebrow: "Subscription Discovery",
                            title: "Scan connected email accounts for subscriptions.",
                            detail: "Account setup and deletion now live in Settings. This screen only runs automatic scans and shows subscription suggestions for review."
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        autoDiscoveryHero
                            .padding(.horizontal, 20)

                        scanPanel
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Email Auto Scan")
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
            .fullScreenCover(isPresented: $showingScanExperience) {
                EmailScanProgressView(
                    scanState: scanState,
                    findings: liveFindings,
                    liveFindingCount: liveFindingCount
                )
                    .interactiveDismissDisabled(scanState.isScanning)
            }
            .sheet(isPresented: $showingResults) {
                NavigationStack {
                    EmailScanResultsView(
                        findings: $findings,
                        templates: templates,
                        onImported: { remainingCount in
                            liveFindings = findings
                            statusMessage = remainingCount == 0
                                ? PMLocalized("Suggestion imported. No remaining email suggestions.")
                                : PMLocalized("Suggestion imported. %d email suggestion(s) remain.", remainingCount)
                        }
                    )
                }
            }
        }
    }

    private var autoDiscoveryHero: some View {
        PayGuardPanel(
            title: "Email scan only",
            symbol: "envelope.badge.shield.half.filled",
            detail: "Connected mailboxes are managed in Settings. Run discovery here to scan mailbox history for receipts, renewals, invoices, billing notices, and cancellation signals."
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PayGuardMetricBadge(title: "Accounts", value: "\(accounts.count)")
                PayGuardMetricBadge(title: "Mode", value: "Auto scan")
                PayGuardMetricBadge(title: "Saving", value: "Review first")
                PayGuardMetricBadge(title: "Setup", value: "Settings")
            }

            if accounts.isEmpty {
                Text("No email account is connected yet. Open Settings > Email accounts to add Gmail, iCloud Mail, Outlook, Yahoo, Proton Bridge, or another IMAP mailbox.".localizedKey)
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(scanCursorSummary)
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scanPanel: some View {
        PayGuardPanel(
            title: "Automatic scan",
            symbol: "waveform.path.ecg.rectangle.fill",
            detail: accounts.isEmpty ? "No connected email account is available. Add or delete accounts from Settings." : "PayGuard scans the accounts configured in Settings. It does not save subscriptions until you approve a suggestion."
        ) {
            if case .scanning(let accountName, let index, let total) = scanState {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(PMLocalized("Scanning %@…", accountName))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                    }

                    ProgressView(value: Double(index), total: Double(total))
                        .tint(PayGuardTheme.accent)

                    Text(PMLocalized("Account %d of %d. PayGuard is checking connected mailboxes and parsing invoice, renewal, and cancellation emails.", index, total))
                        .font(PayGuardTheme.captionFont)
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("This can take a little while on the first scan because PayGuard checks the selected mailbox history and confirms recurring results one by one.".localizedKey)
                        .font(PayGuardTheme.captionFont)
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if accounts.isEmpty {
                    dismiss()
                    appRouter.openSettings(.emailAccounts)
                } else {
                    startAutomaticScan()
                }
            } label: {
                Label(accounts.isEmpty ? "Add email account in Settings" : "Auto scan connected email accounts", systemImage: "mail.stack.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(scanState.isScanning)

            if hasSavedScanCursor {
                Button {
                    resetScanHistoryAndRescan()
                } label: {
                    Label("Reset scan history and rescan all emails", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(scanState.isScanning)
            }
        }
    }

    private var findingsPanel: some View {
        PayGuardPanel(
            title: "Found subscription emails",
            symbol: "sparkles.rectangle.stack.fill",
            detail: "These are automatically detected from connected mailbox content. Open one to review the suggested subscription fields."
        ) {
            VStack(spacing: 12) {
                ForEach(findings) { finding in
                    Button {
                        showingResults = true
                    } label: {
                        EmailFindingRow(finding: finding)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hasSavedScanCursor: Bool {
        accounts.contains(where: { $0.lastScanAt != nil })
    }

    private var scanCursorSummary: String {
        let scannedAccounts = accounts.compactMap { account -> String? in
            guard let lastScanAt = account.lastScanAt else { return nil }
            return PMLocalized("%@ since %@", account.displayName, PayGuardFormatters.mediumDate.string(from: lastScanAt))
        }

        guard !scannedAccounts.isEmpty else {
            return PMLocalized("The first scan checks your connected mailbox history. Later scans only look for newer emails, and you can reset that history anytime.")
        }

        return PMLocalized("Next scans start from the saved scan date for each account: %@. Use reset if you want a full mailbox scan again.", scannedAccounts.joined(separator: " • "))
    }

    private func resetScanHistoryAndRescan() {
        for account in accounts {
            account.lastScanAt = nil
            account.lastScanStatus = PMLocalized("Ready for full mailbox scan")
            account.updatedAt = .now
        }
        try? modelContext.save()
        startAutomaticScan()
    }

    private func startAutomaticScan() {
        guard !accounts.isEmpty else {
            statusMessage = PMLocalized("Connect an email account first.")
            return
        }

        findings = []
        liveFindings = []
        liveFindingCount = 0
        statusMessage = nil
        showingResults = false
        showingScanExperience = true

        Task {
            var allFindings: [EmailScanFinding] = []
            let scanConfiguration = EmailScanConfiguration()
            for (offset, account) in accounts.enumerated() {
                await MainActor.run {
                    scanState = .scanning(account.displayName, offset + 1, accounts.count)
                }
                do {
                    let snapshot = EmailAccountConnectionSnapshot(account: account)
                    let accountFindings = try await EmailAutoDiscoveryService.shared.scan(
                        account: snapshot,
                        configuration: scanConfiguration,
                        onProgress: { progressFindings in
                            await MainActor.run {
                                liveFindings = progressFindings.sorted { $0.confidence > $1.confidence }
                                liveFindingCount = liveFindings.count
                            }
                        }
                    )
                    allFindings.append(contentsOf: accountFindings)
                    await MainActor.run {
                        liveFindings = allFindings.sorted { $0.confidence > $1.confidence }
                        liveFindingCount = liveFindings.count
                        account.lastScanAt = .now
                        account.lastScanStatus = PMLocalized("Found %d active subscription suggestions", accountFindings.count)
                        account.updatedAt = .now
                        try? modelContext.save()
                    }
                } catch {
                    await MainActor.run {
                        if let discoveryError = error as? EmailAutoDiscoveryError,
                           case .noMessagesFound = discoveryError {
                            account.lastScanAt = .now
                            account.lastScanStatus = PMLocalized("Scanned mailbox history. No active subscription emails found.")
                        } else {
                            account.lastScanStatus = error.localizedDescription
                        }
                        account.updatedAt = .now
                        try? modelContext.save()
                    }
                }

                if shouldStopScanningAfterCurrentAccount(allFindings) {
                    break
                }
            }

            await MainActor.run {
                findings = allFindings.sorted { $0.confidence > $1.confidence }
                liveFindings = findings
                liveFindingCount = findings.count
                scanState = .idle
                showingScanExperience = false
                showingResults = !findings.isEmpty
                statusMessage = findings.isEmpty
                    ? PMLocalized("No active subscription emails were found. PayGuard checked the connected mailboxes and skipped cancelled or one-time items.")
                    : PMLocalized("Found %d active subscription suggestions across connected accounts.", findings.count)
            }
        }
    }

    private func shouldStopScanningAfterCurrentAccount(_ findings: [EmailScanFinding]) -> Bool {
        let uniqueServices = Set(findings.map { $0.subject.normalizedLookupKey })
        let highConfidenceCount = findings.filter { $0.confidence >= 0.86 }.count
        return uniqueServices.count >= 6 || highConfidenceCount >= 8
    }
}

private enum EmailScanState: Equatable {
    case idle
    case scanning(String, Int, Int)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

private struct EmailScanProgressView: View {
    let scanState: EmailScanState
    let findings: [EmailScanFinding]
    let liveFindingCount: Int

    var body: some View {
        NavigationStack {
            ZStack {
                PayGuardBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionTitleView(
                            eyebrow: "Premium Discovery",
                            title: "Scanning your connected mailboxes.",
                            detail: "This can take a little while because PayGuard scans the selected mailbox history for recurring invoices, renewals, and billing signals."
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        PayGuardPanel(
                            title: "Live progress",
                            symbol: "sparkles",
                            detail: "The counter increases as recurring subscriptions are confirmed."
                        ) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(PayGuardTheme.accent.opacity(0.16))
                                            .frame(width: 54, height: 54)
                                        ProgressView()
                                            .tint(PayGuardTheme.accent)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(PMLocalized("%d subscription(s) found", liveFindingCount))
                                            .font(.system(.headline, design: .rounded, weight: .bold))
                                            .foregroundStyle(PayGuardTheme.textPrimary)
                                        Text(progressDetailText)
                                            .font(PayGuardTheme.captionFont)
                                            .foregroundStyle(PayGuardTheme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }

                                if case .scanning(_, let index, let total) = scanState {
                                    ProgressView(value: Double(index), total: Double(total))
                                        .tint(PayGuardTheme.accent)
                                }

                                Text("If the selected mailbox has a long history, the first scan can take longer. Later scans are usually much faster.".localizedKey)
                                    .font(PayGuardTheme.captionFont)
                                    .foregroundStyle(PayGuardTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 20)

                        PayGuardPanel(
                            title: findings.isEmpty ? "Waiting for subscriptions" : "Subscriptions found",
                            symbol: "mail.stack.fill",
                            detail: findings.isEmpty
                                ? "PayGuard will list recurring subscriptions here as soon as they are confirmed."
                                : "Each confirmed recurring subscription is listed immediately."
                        ) {
                            VStack(spacing: 12) {
                                if findings.isEmpty {
                                    Text("No confirmed subscriptions yet. PayGuard is still scanning your connected inboxes.".localizedKey)
                                        .font(PayGuardTheme.captionFont)
                                        .foregroundStyle(PayGuardTheme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                } else {
                                    ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text("\(index + 1).")
                                                .font(.system(.headline, design: .rounded, weight: .bold))
                                                .foregroundStyle(PayGuardTheme.accent)
                                                .frame(width: 28, alignment: .leading)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(finding.detectedServiceName ?? finding.subject)
                                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                                    .foregroundStyle(PayGuardTheme.textPrimary)
                                                Text(progressSummary(for: finding))
                                                    .font(PayGuardTheme.captionFont)
                                                    .foregroundStyle(PayGuardTheme.textSecondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }

                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(PayGuardTheme.surfaceSecondary)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(PayGuardTheme.stroke, lineWidth: 1)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Scanning")
            .navigationBarTitleDisplayMode(.inline)
            .payGuardNavigationChrome()
        }
    }

    private var progressDetailText: String {
        switch scanState {
        case .idle:
            return PMLocalized("Wrapping up your scan results.")
        case .scanning(let accountName, let index, let total):
            return PMLocalized("Scanning %@. Account %d of %d.", accountName, index, total)
        }
    }

    private func progressSummary(for finding: EmailScanFinding) -> String {
        let cycle = finding.detectedBillingCycle?.label ?? PMLocalized("Recurring")
        if let nextPaymentDate = finding.detectedNextPaymentDate {
            return PMLocalized("%@ • Next payment %@", cycle, PayGuardFormatters.mediumDate.string(from: nextPaymentDate))
        }
        return cycle
    }
}

private struct EmailScanResultsView: View {
    @Environment(PremiumAccessController.self) private var premiumAccess
    @Binding var findings: [EmailScanFinding]
    let templates: [ServiceTemplate]
    let onImported: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editorDraft: SubscriptionImportDraft?
    @State private var selectedFindingID: UUID?
    @State private var premiumGate: PremiumGate?

    var body: some View {
        ZStack {
            PayGuardBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitleView(
                        eyebrow: "Scan Complete",
                        title: "Found recurring subscriptions.",
                        detail: "These are the weekly, monthly, and yearly subscriptions PayGuard confirmed from your email accounts."
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    PayGuardPanel(
                        title: PMLocalized("%d subscription(s) ready", findings.count),
                        symbol: "checkmark.seal.fill",
                        detail: "Tap any item to open the editor directly and fine-tune the fields before saving."
                    ) {
                        if findings.isEmpty {
                            Text("All detected suggestions have been reviewed or imported.".localizedKey)
                                .font(PayGuardTheme.captionFont)
                                .foregroundStyle(PayGuardTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 12) {
                                if !premiumAccess.isLifetimeUnlocked && !premiumAccess.canUseSmartImport() {
                                    Text(PMLocalized("Free plan already used its 1 email import. Tap any remaining suggestion to unlock Lifetime Pro and add the rest."))
                                        .font(PayGuardTheme.captionFont)
                                        .foregroundStyle(PayGuardTheme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.bottom, 4)
                                }

                                ForEach(findings) { finding in
                                    Button {
                                        guard premiumAccess.canUseSmartImport() else {
                                            premiumGate = .smartImport
                                            return
                                        }
                                        selectedFindingID = finding.id
                                        editorDraft = SubscriptionImportDraft.make(from: finding, templates: templates)
                                    } label: {
                                        EmailFindingRow(finding: finding)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Found subscriptions")
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
        .sheet(item: $editorDraft) { draft in
            NavigationStack {
                SubscriptionEditorView(importDraft: draft) {
                    guard let selectedFindingID else { return }
                    premiumAccess.registerSmartImportIfNeeded()
                    findings.removeAll { $0.id == selectedFindingID }
                    onImported(findings.count)
                    self.selectedFindingID = nil
                }
            }
        }
        .sheet(item: $premiumGate) { gate in
            PremiumUpgradeSheet(gate: gate)
        }
    }
}

private struct EmailFindingRow: View {
    let finding: EmailScanFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PayGuardTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.detectedServiceName ?? finding.subject)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                        .lineLimit(2)
                    Text("\(finding.sender) • \(finding.accountLabel)")
                        .font(PayGuardTheme.captionFont)
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .lineLimit(2)
                    if let detectedNextPaymentDate = finding.detectedNextPaymentDate,
                       let detectedBillingCycle = finding.detectedBillingCycle,
                       detectedBillingCycle.isRecurring {
                        Text(PMLocalized("%@ • Next payment %@", detectedBillingCycle.label, PayGuardFormatters.mediumDate.string(from: detectedNextPaymentDate)))
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(PayGuardTheme.accent.opacity(0.9))
                            .lineLimit(2)
                    }
                }

                Spacer()

                Text("\(Int(finding.confidence * 100))%")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(PayGuardTheme.accent.opacity(0.12)))
            }

            Text(finding.preview)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(PayGuardTheme.textSecondary)
                .lineLimit(4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}

private struct EmailProviderCard: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title.localizedKey)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(detail.localizedKey)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}
