//
//  PremiumAccessController.swift
//  PayGuard
//
//  Created by Ali Ozkul on 02.05.26.
//

import Observation
import StoreKit
import SwiftUI

private typealias StoreTransaction = StoreKit.Transaction

enum PremiumGate: String, Identifiable {
    case subscriptionLimit
    case purchaseLimit
    case smartImport
    case scanLimit
    case familyManagement
    case multipleReminders
    case advancedSummaries
    case premiumWidgets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscriptionLimit:
            PMLocalized("Unlock more subscriptions")
        case .purchaseLimit:
            PMLocalized("Unlock more tracked purchases")
        case .smartImport:
            PMLocalized("Smart Import limit reached")
        case .scanLimit:
            PMLocalized("Document scans are limited")
        case .familyManagement:
            PMLocalized("Family management is in Pro")
        case .multipleReminders:
            PMLocalized("Multiple reminders are in Pro")
        case .advancedSummaries:
            PMLocalized("Advanced summaries are in Pro")
        case .premiumWidgets:
            PMLocalized("Unlock premium widgets")
        }
    }

    var detail: String {
        switch self {
        case .subscriptionLimit:
            PMLocalized("Free includes up to %d active subscriptions. Unlock Lifetime Pro for unlimited tracking.", PremiumAccessController.freeSubscriptionLimit)
        case .purchaseLimit:
            PMLocalized("Free includes up to %d active protected purchases. Unlock Lifetime Pro for unlimited records.", PremiumAccessController.freePurchaseLimit)
        case .smartImport:
            PMLocalized("Free includes %d smart import. Unlock Lifetime Pro for unlimited receipt, screenshot, and PDF imports.", PremiumAccessController.freeSmartImportLimit)
        case .scanLimit:
            PMLocalized("Free includes %d document scan. Unlock Lifetime Pro for unlimited scans across subscriptions and protected purchases.", PremiumAccessController.freeScanLimit)
        case .familyManagement:
            PMLocalized("Assign owners and payers, manage members, and keep the household view organized with Lifetime Pro.")
        case .multipleReminders:
            PMLocalized("Free includes one reminder timing per alert. Lifetime Pro unlocks multiple reminder timings.")
        case .advancedSummaries:
            PMLocalized("Keep the essentials on the free plan, then unlock charts, action recommendations, and deeper household summaries with Pro.")
        case .premiumWidgets:
            PMLocalized("Put live monthly totals, next charges, and action cues on your Home Screen with Lifetime Pro.")
        }
    }
}

struct PremiumFeatureRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private enum PremiumAccessError: Error {
    case unverifiedTransaction
}

@MainActor
@Observable
final class PremiumAccessController {
    static let lifetimeProductID = "com.aliorkunozkul.payguard.lifetime.pro"
    static let freeSubscriptionLimit = 2
    static let freePurchaseLimit = 2
    static let freeScanLimit = 2
    static let freeSmartImportLimit = 1
    static let fallbackLifetimePriceDisplay = "€5.99"

    private let unlockedDefaultsKey = "premiumLifetimeUnlocked"
    private let freeScanUsageDefaultsKey = "premiumFreeScanUsageCount"
    private let freeSmartImportUsageDefaultsKey = "premiumFreeSmartImportUsageCount"

    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    var currentEntitlements: [AppStoreEntitlement] = []
    var lifetimeProduct: Product?
    var isLifetimeUnlocked: Bool
    var freeScanUsageCount: Int
    var freeSmartImportUsageCount: Int
    var isLoadingStore = false
    var isPurchaseInFlight = false
    var hasLoadedStore = false

    init() {
        isLifetimeUnlocked = AppStoreCaptureConfiguration.forcesPremiumUnlock || UserDefaults.standard.bool(forKey: unlockedDefaultsKey)
        freeScanUsageCount = UserDefaults.standard.integer(forKey: freeScanUsageDefaultsKey)
        freeSmartImportUsageCount = UserDefaults.standard.integer(forKey: freeSmartImportUsageDefaultsKey)
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func start() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task { [weak self] in
            for await result in StoreTransaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }

        Task {
            await refreshEntitlements()
            await loadProductsIfNeeded()
        }
    }

    func canAddSubscription(activeCount: Int) -> Bool {
        isLifetimeUnlocked || activeCount < Self.freeSubscriptionLimit
    }

    func canAddPurchase(activeCount: Int) -> Bool {
        isLifetimeUnlocked || activeCount < Self.freePurchaseLimit
    }

    func canUseSmartImport() -> Bool {
        isLifetimeUnlocked || freeSmartImportUsageCount < Self.freeSmartImportLimit
    }

    func canUseDocumentScan() -> Bool {
        isLifetimeUnlocked || freeScanUsageCount < Self.freeScanLimit
    }

    func canUseFamilyManagement() -> Bool {
        isLifetimeUnlocked
    }

    func canUseAdvancedSummaries() -> Bool {
        isLifetimeUnlocked
    }

    func canUsePremiumWidgets() -> Bool {
        isLifetimeUnlocked
    }

    func supportsMultipleReminders() -> Bool {
        isLifetimeUnlocked
    }

    func loadProductsIfNeeded() async {
        guard !hasLoadedStore else { return }
        await loadProducts()
    }

    func loadProducts() async {
        isLoadingStore = true
        defer {
            isLoadingStore = false
            hasLoadedStore = true
        }

        do {
            lifetimeProduct = try await Product.products(for: [Self.lifetimeProductID]).first
        } catch {
            lifetimeProduct = nil
        }
    }

    func refreshEntitlements() async {
        if AppStoreCaptureConfiguration.forcesPremiumUnlock {
            currentEntitlements = [
                AppStoreEntitlement(
                    id: Self.lifetimeProductID,
                    productID: Self.lifetimeProductID,
                    kind: PMLocalized("Non-consumable"),
                    expirationDate: nil
                )
            ]
            isLifetimeUnlocked = true
            UserDefaults.standard.set(true, forKey: unlockedDefaultsKey)
            return
        }

        do {
            currentEntitlements = try await AppStoreSyncService.currentEntitlements()
            let unlocked = currentEntitlements.contains { $0.productID == Self.lifetimeProductID }
            isLifetimeUnlocked = unlocked
            UserDefaults.standard.set(unlocked, forKey: unlockedDefaultsKey)
        } catch {
            currentEntitlements = []
        }
    }

    func purchaseLifetime() async -> String {
        await loadProductsIfNeeded()

        guard let lifetimeProduct else {
            return PMLocalized("Lifetime Pro is not available yet. Check the product setup in App Store Connect.")
        }

        isPurchaseInFlight = true
        defer { isPurchaseInFlight = false }

        do {
            let result = try await lifetimeProduct.purchase()

            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                await transaction.finish()
                await refreshEntitlements()

                if isLifetimeUnlocked {
                    return PMLocalized("Lifetime Pro is now unlocked.")
                }
                return PMLocalized("The purchase completed, but the Pro unlock has not appeared yet. Try Restore Purchases.")
            case .pending:
                return PMLocalized("This purchase is pending approval.")
            case .userCancelled:
                return PMLocalized("The purchase was cancelled.")
            @unknown default:
                return PMLocalized("The purchase could not be completed.")
            }
        } catch {
            return PMLocalized("The purchase could not be completed.")
        }
    }

    func restorePurchases() async -> String {
        isLoadingStore = true
        defer { isLoadingStore = false }

        do {
            _ = try await AppStoreSyncService.syncOwnPurchases()
            await refreshEntitlements()
            return isLifetimeUnlocked
                ? PMLocalized("Lifetime Pro has been restored.")
                : PMLocalized("No Lifetime Pro purchase was found for this Apple Account yet.")
        } catch {
            return PMLocalized("Restore Purchases could not finish right now.")
        }
    }

    var lifetimePriceLabel: String {
        if let displayPrice = lifetimeProduct?.displayPrice {
            return displayPrice
        }
        if hasLoadedStore {
            return Self.fallbackLifetimePriceDisplay
        }
        return PMLocalized("Loading price")
    }

    var upgradeFeatures: [PremiumFeatureRow] {
        [
            PremiumFeatureRow(
                title: PMLocalized("Unlimited tracking"),
                detail: PMLocalized("Save as many subscriptions and protected purchases as you need.")
            ),
            PremiumFeatureRow(
                title: PMLocalized("Smart Import"),
                detail: PMLocalized("Import screenshots, receipts, and PDFs into prefilled drafts.")
            ),
            PremiumFeatureRow(
                title: PMLocalized("Unlimited scans"),
                detail: PMLocalized("Scan receipts and paper invoices into PDF attachments whenever you need.")
            ),
            PremiumFeatureRow(
                title: PMLocalized("Family management"),
                detail: PMLocalized("Assign payers and owners and manage household members.")
            ),
            PremiumFeatureRow(
                title: PMLocalized("Premium widgets"),
                detail: PMLocalized("Keep live monthly totals, next charges, and top priorities on your Home Screen.")
            ),
            PremiumFeatureRow(
                title: PMLocalized("Advanced summaries"),
                detail: PMLocalized("Unlock action recommendations, charts, and deeper cost views.")
            )
        ]
    }

    func clampedOffsets(from selection: Set<Int>) -> Set<Int> {
        guard !supportsMultipleReminders() else { return selection }
        guard let preservedOffset = selection.sorted(by: >).first else { return [] }
        return [preservedOffset]
    }

    func registerDocumentScanIfNeeded() {
        guard !isLifetimeUnlocked else { return }
        freeScanUsageCount += 1
        UserDefaults.standard.set(freeScanUsageCount, forKey: freeScanUsageDefaultsKey)
    }

    func registerSmartImportIfNeeded() {
        guard !isLifetimeUnlocked else { return }
        freeSmartImportUsageCount += 1
        UserDefaults.standard.set(freeSmartImportUsageCount, forKey: freeSmartImportUsageDefaultsKey)
    }

    func resetLocalUsageState() {
        freeScanUsageCount = 0
        UserDefaults.standard.removeObject(forKey: freeScanUsageDefaultsKey)
        freeSmartImportUsageCount = 0
        UserDefaults.standard.removeObject(forKey: freeSmartImportUsageDefaultsKey)
    }

    private func verifiedTransaction(from result: VerificationResult<StoreTransaction>) throws -> StoreTransaction {
        switch result {
        case .verified(let transaction):
            transaction
        case .unverified:
            throw PremiumAccessError.unverifiedTransaction
        }
    }
}

struct PremiumUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PremiumAccessController.self) private var premiumAccess

    let gate: PremiumGate

    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitleView(
                        eyebrow: "PayGuard Pro",
                        title: gate.title,
                        detail: gate.detail
                    )

                    PayGuardPanel(
                        title: premiumAccess.isLifetimeUnlocked ? "Lifetime unlocked" : "One-time unlock",
                        symbol: premiumAccess.isLifetimeUnlocked ? "checkmark.seal.fill" : "sparkles.rectangle.stack.fill",
                        detail: premiumAccess.isLifetimeUnlocked
                            ? "Everything in PayGuard Pro is available on this device."
                            : "Buy once and keep the full PayGuard toolkit unlocked."
                    ) {
                        PayGuardMetricBadge(title: "Price", value: premiumAccess.lifetimePriceLabel)

                        ForEach(premiumAccess.upgradeFeatures) { feature in
                            PremiumFeatureBullet(feature: feature)
                        }

                        if premiumAccess.isLifetimeUnlocked {
                            Button("Close") {
                                dismiss()
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                        } else {
                            Button {
                                Task {
                                    statusMessage = await premiumAccess.purchaseLifetime()
                                    if premiumAccess.isLifetimeUnlocked {
                                        dismiss()
                                    }
                                }
                            } label: {
                                if premiumAccess.isPurchaseInFlight {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text(PMLocalized("Unlock Lifetime Pro"))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                            .disabled(premiumAccess.isPurchaseInFlight)

                            Button {
                                Task {
                                    statusMessage = await premiumAccess.restorePurchases()
                                }
                            } label: {
                                Text("Restore Purchases")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(premiumAccess.isPurchaseInFlight)
                        }
                    }
                }
                .padding(20)
            }
            .background(PayGuardBackdrop())
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .payGuardNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarCircleIcon(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .task {
                premiumAccess.start()
                await premiumAccess.loadProductsIfNeeded()
            }
            .alert("Purchase Update", isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
        }
    }
}

struct PremiumFeatureBullet: View {
    let feature: PremiumFeatureRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(feature.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
        }
    }
}

struct FreePlanUsageBanner: View {
    let title: String
    let detail: String
    let currentCount: Int
    let limit: Int
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.localizedKey)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    Text(detail.localizedKey)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
                Spacer()
                PayGuardTag(title: PMLocalized("%d/%d used", currentCount, limit))
            }

            Button("Unlock Pro") {
                onUnlock()
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}


struct CompactFreePlanStatusBar: View {
    let title: String
    let detail: String
    let currentCount: Int
    let limit: Int
    let onUnlock: () -> Void

    private var progress: Double {
        guard limit > 0 else { return 0 }
        return min(Double(currentCount) / Double(limit), 1)
    }

    var body: some View {
        Button {
            onUnlock()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(PayGuardTheme.stroke.opacity(0.72), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(PayGuardTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PayGuardTheme.accent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.localizedKey)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    Text(detail.localizedKey)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(PMLocalized("%d/%d used", currentCount, limit))
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(PayGuardTheme.accent.opacity(0.12))
                    )

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PayGuardTheme.surface.opacity(0.74))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PayGuardTheme.stroke.opacity(0.62), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Unlock Pro"))
    }
}

struct PremiumLockedCard: View {
    let title: String
    let detail: String
    let buttonTitle: String
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title.localizedKey, systemImage: "lock.fill")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.textPrimary)

            Text(detail.localizedKey)
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)

            Button(buttonTitle.localizedKey) {
                onUnlock()
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
        .padding(18)
        .payGuardCardStyle()
    }
}
