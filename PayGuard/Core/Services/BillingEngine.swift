//
//  BillingEngine.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation

struct CategoryTotal: Identifiable {
    let id = UUID()
    let category: SubscriptionCategory
    let total: Decimal
}

struct MemberTotal: Identifiable {
    let id = UUID()
    let name: String
    let total: Decimal
}

struct HealthInsight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

struct HouseholdBalanceRow: Identifiable {
    let id = UUID()
    let name: String
    let paid: Decimal
    let owned: Decimal

    var delta: Decimal {
        paid - owned
    }
}

enum DashboardActionDestination {
    case subscription(UUID)
    case purchase(UUID)
}

struct DashboardActionRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let actionLabel: String
    let priority: Int
    let destination: DashboardActionDestination
}

struct DashboardSnapshot {
    let monthlyTotal: Decimal
    let yearlyTotal: Decimal
    let topSubscriptions: [SubscriptionRecord]
    let upcomingSubscriptions: [SubscriptionRecord]
    let categoryTotals: [CategoryTotal]
    let memberTotals: [MemberTotal]
    let healthScore: Int
    let healthInsights: [HealthInsight]
    let protectedPurchaseValue: Decimal
    let upcomingReturns: [PurchaseRightItem]
    let expiringWarranties: [PurchaseRightItem]
    let householdBalances: [HouseholdBalanceRow]
    let actionRecommendations: [DashboardActionRecommendation]
}

final class BillingEngine {
    static let shared = BillingEngine()

    private let calendar = Calendar.current

    func nextPaymentDate(
        from currentDate: Date,
        cycle: BillingCycle,
        customIntervalDays: Int
    ) -> Date {
        switch cycle {
        case .oneTime:
            currentDate
        case .weekly:
            calendar.date(byAdding: .day, value: 7, to: currentDate) ?? currentDate
        case .monthly:
            calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        case .quarterly:
            calendar.date(byAdding: .month, value: 3, to: currentDate) ?? currentDate
        case .yearly:
            calendar.date(byAdding: .year, value: 1, to: currentDate) ?? currentDate
        case .custom:
            calendar.date(byAdding: .day, value: customIntervalDays, to: currentDate) ?? currentDate
        }
    }

    func monthlyEquivalent(for subscription: SubscriptionRecord) -> Decimal {
        switch subscription.billingCycle {
        case .oneTime:
            return .zero
        case .weekly:
            return subscription.amount * Decimal(52) / Decimal(12)
        case .monthly:
            return subscription.amount
        case .quarterly:
            return subscription.amount / Decimal(3)
        case .yearly:
            return subscription.amount / Decimal(12)
        case .custom:
            let monthlyFactor = Decimal(30) / Decimal(max(subscription.customIntervalDays, 1))
            return subscription.amount * monthlyFactor
        }
    }

    func yearlyEquivalent(for subscription: SubscriptionRecord) -> Decimal {
        monthlyEquivalent(for: subscription) * Decimal(12)
    }

    func snapshot(
        subscriptions: [SubscriptionRecord],
        purchases: [PurchaseRightItem],
        members: [FamilyMember] = []
    ) -> DashboardSnapshot {
        let activeSubscriptions = subscriptions.filter { !$0.isArchived }
        let activePurchases = purchases.filter { !$0.isArchived }
        let memberNameByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.name) })

        let monthlyTotal = activeSubscriptions.reduce(into: Decimal.zero) { partial, item in
            partial += monthlyEquivalent(for: item)
        }
        let yearlyTotal = activeSubscriptions.reduce(into: Decimal.zero) { partial, item in
            partial += yearlyEquivalent(for: item)
        }

        let categoryTotals = Dictionary(grouping: activeSubscriptions, by: \.category)
            .map { key, value in
                CategoryTotal(
                    category: key,
                    total: value.reduce(into: Decimal.zero) { total, item in
                        total += monthlyEquivalent(for: item)
                    }
                )
            }
            .sorted { $0.total > $1.total }

        let memberTotals = Dictionary(grouping: activeSubscriptions) { subscription in
            resolvedMemberName(id: subscription.payerMemberID, fallback: subscription.payerName, memberNameByID: memberNameByID)
        }
            .map { name, items in
                MemberTotal(
                    name: name,
                    total: items.reduce(into: Decimal.zero) { total, item in
                        total += monthlyEquivalent(for: item)
                    }
                )
            }
            .sorted { $0.total > $1.total }

        let upcomingSubscriptions = activeSubscriptions
            .sorted { $0.nextPaymentDate < $1.nextPaymentDate }
            .prefix(6)
            .map { $0 }

        let topSubscriptions = activeSubscriptions
            .sorted { monthlyEquivalent(for: $0) > monthlyEquivalent(for: $1) }
            .prefix(4)
            .map { $0 }

        let upcomingReturns = activePurchases
            .sorted { $0.returnDeadline < $1.returnDeadline }
            .filter { $0.hasReturnWindow && $0.returnDeadline >= .now.startOfDay }
            .prefix(4)
            .map { $0 }

        let expiringWarranties = activePurchases
            .sorted { $0.warrantyEndDate < $1.warrantyEndDate }
            .filter { $0.hasWarrantyCoverage && $0.warrantyEndDate >= .now.startOfDay }
            .prefix(4)
            .map { $0 }

        let protectedPurchaseValue = activePurchases.reduce(into: Decimal.zero) { total, item in
            if item.hasWarrantyCoverage && item.warrantyEndDate >= .now.startOfDay {
                total += item.price
            }
        }

        let duplicates = Dictionary(grouping: activeSubscriptions, by: { $0.name.normalizedLookupKey })
            .filter { $0.value.count > 1 }
            .count

        let highCostCount = activeSubscriptions.filter { monthlyEquivalent(for: $0) > Decimal(20) }.count
        let renewalsSoonCount = activeSubscriptions.filter {
            guard $0.billingCycle.isRecurring else { return false }
            let days = calendar.dateComponents([.day], from: .now.startOfDay, to: $0.nextPaymentDate.startOfDay).day ?? 99
            return days >= 0 && days <= 7
        }.count
        let unusedSignals = max(0, activeSubscriptions.count - Set(activeSubscriptions.map(\.category)).count)

        let deductions = (duplicates * 10) + (highCostCount * 4) + (renewalsSoonCount * 3) + (unusedSignals * 2)
        let healthScore = max(0, min(100, 92 - deductions))

        var insights: [HealthInsight] = []
        if duplicates > 0 {
            insights.append(HealthInsight(
                title: PMLocalized("Duplicate services"),
                detail: PMLocalized("You have %d possible overlap(s) to review.", duplicates)
            ))
        }
        if renewalsSoonCount > 0 {
            insights.append(HealthInsight(
                title: PMLocalized("Renewals this week"),
                detail: PMLocalized("%d payments are approaching soon.", renewalsSoonCount)
            ))
        }
        if highCostCount > 0 {
            insights.append(HealthInsight(
                title: PMLocalized("High monthly spend"),
                detail: PMLocalized("%d subscriptions are above your cost comfort zone.", highCostCount)
            ))
        }
        if insights.isEmpty {
            insights.append(HealthInsight(
                title: PMLocalized("Healthy baseline"),
                detail: PMLocalized("No urgent waste signal was detected across active plans.")
            ))
        }

        var paidByMember: [String: Decimal] = [:]
        var ownedByMember: [String: Decimal] = [:]
        activeSubscriptions.forEach { subscription in
            let monthly = monthlyEquivalent(for: subscription)
            let payerName = resolvedMemberName(id: subscription.payerMemberID, fallback: subscription.payerName, memberNameByID: memberNameByID)
            let ownerName = resolvedMemberName(id: subscription.ownerMemberID, fallback: subscription.ownerName, memberNameByID: memberNameByID)
            paidByMember[payerName, default: .zero] += monthly
            ownedByMember[ownerName, default: .zero] += monthly
        }

        let householdBalances = Set(paidByMember.keys).union(ownedByMember.keys)
            .sorted()
            .map { name in
                HouseholdBalanceRow(
                    name: name,
                    paid: paidByMember[name, default: .zero],
                    owned: ownedByMember[name, default: .zero]
                )
            }
            .sorted { abs($0.delta.doubleValue) > abs($1.delta.doubleValue) }

        var actionRecommendations: [DashboardActionRecommendation] = []

        let renewalsSoon = activeSubscriptions
            .filter {
                guard $0.billingCycle.isRecurring else { return false }
                let days = calendar.dateComponents([.day], from: .now.startOfDay, to: $0.nextPaymentDate.startOfDay).day ?? 99
                return days >= 0 && days <= 7
            }
            .sorted { $0.nextPaymentDate < $1.nextPaymentDate }

        renewalsSoon.prefix(2).forEach { subscription in
            actionRecommendations.append(
                DashboardActionRecommendation(
                    title: PMLocalized("Review %@ before renewal", subscription.name),
                    detail: PMLocalized(
                        "Charges %@ for %@.",
                        subscription.nextPaymentDate.shortRelativeDescription.lowercased(),
                        subscription.amount.currencyString(code: subscription.currencyCode)
                    ),
                    actionLabel: PMLocalized("Open subscription"),
                    priority: 0,
                    destination: .subscription(subscription.id)
                )
            )
        }

        let duplicateGroups = Dictionary(grouping: activeSubscriptions, by: { $0.name.normalizedLookupKey })
            .filter { $0.value.count > 1 }
            .sorted { $0.value.count > $1.value.count }

        duplicateGroups.prefix(2).forEach { _, duplicates in
            guard let lead = duplicates.sorted(by: { monthlyEquivalent(for: $0) > monthlyEquivalent(for: $1) }).first else { return }
            actionRecommendations.append(
                DashboardActionRecommendation(
                    title: PMLocalized("Possible overlap: %@", lead.name),
                    detail: PMLocalized("%d similar subscriptions appear active. Review whether you still need all of them.", duplicates.count),
                    actionLabel: PMLocalized("Compare plans"),
                    priority: 1,
                    destination: .subscription(lead.id)
                )
            )
        }

        activeSubscriptions
            .filter { monthlyEquivalent(for: $0) > Decimal(20) }
            .sorted { monthlyEquivalent(for: $0) > monthlyEquivalent(for: $1) }
            .prefix(2)
            .forEach { subscription in
                actionRecommendations.append(
                    DashboardActionRecommendation(
                        title: PMLocalized("High-cost plan worth revisiting"),
                        detail: PMLocalized(
                            "%@ runs about %@ per month.",
                            subscription.name,
                            monthlyEquivalent(for: subscription).currencyString(code: subscription.currencyCode)
                        ),
                        actionLabel: PMLocalized("Review plan"),
                        priority: 2,
                        destination: .subscription(subscription.id)
                    )
                )
            }

        upcomingReturns.prefix(2).forEach { item in
            actionRecommendations.append(
                DashboardActionRecommendation(
                    title: PMLocalized("Return window is about to close"),
                    detail: PMLocalized("%@ can be returned until %@.", item.title, item.returnDeadline.shortRelativeDescription.lowercased()),
                    actionLabel: PMLocalized("Open item"),
                    priority: 0,
                    destination: .purchase(item.id)
                )
            )
        }

        expiringWarranties.prefix(2).forEach { item in
            actionRecommendations.append(
                DashboardActionRecommendation(
                    title: PMLocalized("Warranty ending soon"),
                    detail: PMLocalized("%@ loses coverage %@.", item.title, item.warrantyEndDate.shortRelativeDescription.lowercased()),
                    actionLabel: PMLocalized("Prepare claim"),
                    priority: 1,
                    destination: .purchase(item.id)
                )
            )
        }

        actionRecommendations.sort { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.title < rhs.title
            }
            return lhs.priority < rhs.priority
        }

        return DashboardSnapshot(
            monthlyTotal: monthlyTotal,
            yearlyTotal: yearlyTotal,
            topSubscriptions: topSubscriptions,
            upcomingSubscriptions: upcomingSubscriptions,
            categoryTotals: categoryTotals,
            memberTotals: memberTotals,
            healthScore: healthScore,
            healthInsights: insights,
            protectedPurchaseValue: protectedPurchaseValue,
            upcomingReturns: upcomingReturns,
            expiringWarranties: expiringWarranties,
            householdBalances: householdBalances,
            actionRecommendations: Array(actionRecommendations.prefix(6))
        )
    }

    private func resolvedMemberName(id: UUID?, fallback: String, memberNameByID: [UUID: String]) -> String {
        if let id, let resolved = memberNameByID[id] {
            return resolved
        }
        return fallback
    }
}

extension String {
    var normalizedLookupKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }
}
