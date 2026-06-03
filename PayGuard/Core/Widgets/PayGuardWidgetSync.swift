//
//  PayGuardWidgetSync.swift
//  PayGuard
//
//  Created by Ali Ozkul on 02.05.26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum PayGuardWidgetBridge {
    static let appGroupID = "group.Ali-Orkun-Ozkul.PayGuard.shared"
    static let snapshotKey = "paymind.widget.snapshot"
}

struct PayGuardWidgetSnapshotPayload: Codable {
    let updatedAt: Date
    let isLifetimeUnlocked: Bool
    let hasData: Bool
    let monthlyTotalLabel: String
    let monthlyTotalDisplay: String
    let activePlansLabel: String
    let activePlanCount: Int
    let protectedLabel: String
    let protectedCount: Int
    let attentionLabel: String
    let attentionCount: Int
    let nextChargeLabel: String
    let nextChargeTitle: String?
    let nextChargeDateLabel: String?
    let nextChargeAmountDisplay: String?
    let focusLabel: String
    let focusTitle: String
    let focusDetail: String
    let lockedStateTitle: String
    let lockedStateDetail: String
    let lockedStateBadgeTitle: String
    let emptyStateTitle: String
    let emptyStateDetail: String
}

@MainActor
final class PayGuardWidgetSnapshotStore {
    static let shared = PayGuardWidgetSnapshotStore()

    private let calendar = Calendar.current

    private init() {}

    func sync(
        subscriptions: [SubscriptionRecord],
        purchases: [PurchaseRightItem],
        members: [FamilyMember],
        isLifetimeUnlocked: Bool
    ) {
        let activeSubscriptions = subscriptions.filter { !$0.isArchived }
        let activePurchases = purchases.filter { !$0.isArchived }
        let snapshot = BillingEngine.shared.snapshot(
            subscriptions: subscriptions,
            purchases: purchases,
            members: members
        )

        let payload = buildPayload(
            snapshot: snapshot,
            activeSubscriptions: activeSubscriptions,
            activePurchases: activePurchases,
            isLifetimeUnlocked: isLifetimeUnlocked
        )

        guard let defaults = UserDefaults(suiteName: PayGuardWidgetBridge.appGroupID),
              let data = try? JSONEncoder().encode(payload) else {
            return
        }

        defaults.set(data, forKey: PayGuardWidgetBridge.snapshotKey)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func buildPayload(
        snapshot: DashboardSnapshot,
        activeSubscriptions: [SubscriptionRecord],
        activePurchases: [PurchaseRightItem],
        isLifetimeUnlocked: Bool
    ) -> PayGuardWidgetSnapshotPayload {
        let primaryCurrencyCode = activeSubscriptions.first?.currencyCode ?? "EUR"
        let nextCharge = activeSubscriptions.sorted { $0.nextPaymentDate < $1.nextPaymentDate }.first
        let renewalsThisWeek = activeSubscriptions.filter {
            guard $0.billingCycle.isRecurring else {
                return false
            }
            guard let days = calendar.dateComponents([.day], from: .now.startOfDay, to: $0.nextPaymentDate.startOfDay).day else {
                return false
            }
            return (0...7).contains(days)
        }.count
        let returnsClosingSoon = activePurchases.filter {
            guard $0.hasReturnWindow else {
                return false
            }
            guard let days = calendar.dateComponents([.day], from: .now.startOfDay, to: $0.returnDeadline.startOfDay).day else {
                return false
            }
            return (0...7).contains(days)
        }.count
        let warrantiesEndingSoon = activePurchases.filter {
            guard $0.hasWarrantyCoverage else {
                return false
            }
            guard let days = calendar.dateComponents([.day], from: .now.startOfDay, to: $0.warrantyEndDate.startOfDay).day else {
                return false
            }
            return (0...30).contains(days)
        }.count
        let attentionCount = renewalsThisWeek + returnsClosingSoon + warrantiesEndingSoon

        let focusTitle: String
        let focusDetail: String
        if let topAction = snapshot.actionRecommendations.first {
            focusTitle = topAction.title
            focusDetail = topAction.detail
        } else if let nextCharge {
            focusTitle = PMLocalized("Upcoming payment")
            if nextCharge.billingCycle.isRecurring {
                focusDetail = PMLocalized(
                    "%@ renews %@ for %@.",
                    nextCharge.name,
                    nextCharge.nextPaymentDate.shortRelativeDescription.lowercased(),
                    nextCharge.amount.currencyString(code: nextCharge.currencyCode)
                )
            } else {
                focusDetail = PMLocalized(
                    "%@ is due %@ for %@.",
                    nextCharge.name,
                    nextCharge.nextPaymentDate.shortRelativeDescription.lowercased(),
                    nextCharge.amount.currencyString(code: nextCharge.currencyCode)
                )
            }
        } else {
            focusTitle = PMLocalized("Everything looks calm right now.")
            focusDetail = PMLocalized("No urgent reminder or unusual spend signal is waiting for you.")
        }

        return PayGuardWidgetSnapshotPayload(
            updatedAt: .now,
            isLifetimeUnlocked: isLifetimeUnlocked,
            hasData: !activeSubscriptions.isEmpty || !activePurchases.isEmpty,
            monthlyTotalLabel: PMLocalized("Monthly total"),
            monthlyTotalDisplay: snapshot.monthlyTotal.currencyString(code: primaryCurrencyCode),
            activePlansLabel: PMLocalized("Active plans"),
            activePlanCount: activeSubscriptions.count,
            protectedLabel: PMLocalized("Protected"),
            protectedCount: activePurchases.count,
            attentionLabel: PMLocalized("Needs review"),
            attentionCount: attentionCount,
            nextChargeLabel: PMLocalized("Next charge"),
            nextChargeTitle: nextCharge?.name,
            nextChargeDateLabel: nextCharge?.nextPaymentDate.shortRelativeDescription,
            nextChargeAmountDisplay: nextCharge?.amount.currencyString(code: nextCharge?.currencyCode ?? primaryCurrencyCode),
            focusLabel: PMLocalized("Top priority"),
            focusTitle: focusTitle,
            focusDetail: focusDetail,
            lockedStateTitle: PMLocalized("Premium widgets"),
            lockedStateDetail: PMLocalized("Unlock Lifetime Pro to place live subscription insights, next charges, and action cues on your Home Screen."),
            lockedStateBadgeTitle: PMLocalized("Unlock in app"),
            emptyStateTitle: PMLocalized("No tracked data yet"),
            emptyStateDetail: PMLocalized("Add your first subscription or protected purchase to see live widget insights.")
        )
    }
}
