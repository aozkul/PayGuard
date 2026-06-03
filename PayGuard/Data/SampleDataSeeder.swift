//
//  SampleDataSeeder.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation
import SwiftData

enum SampleDataSeeder {
    static func seedIfNeeded(in modelContext: ModelContext, includeSampleData: Bool) {
        guard includeSampleData else { return }

        let descriptor = FetchDescriptor<SubscriptionRecord>()
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        let subscriptions = [
            SubscriptionRecord(
                name: "Netflix",
                category: .entertainment,
                amount: Decimal(string: "15.99") ?? 15.99,
                billingCycle: .monthly,
                nextPaymentDate: Calendar.current.date(byAdding: .day, value: 4, to: .now) ?? .now,
                source: .quickAdd,
                notes: "Family profile shared with household."
            ),
            SubscriptionRecord(
                name: "Adobe Creative Cloud",
                category: .productivity,
                amount: Decimal(string: "69.99") ?? 69.99,
                billingCycle: .monthly,
                nextPaymentDate: Calendar.current.date(byAdding: .day, value: 12, to: .now) ?? .now,
                payerName: "Ali",
                source: .quickAdd
            ),
            SubscriptionRecord(
                name: "iCloud+",
                category: .cloud,
                amount: Decimal(string: "2.99") ?? 2.99,
                billingCycle: .monthly,
                nextPaymentDate: Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now,
                source: .appStoreGuided
            ),
            SubscriptionRecord(
                name: "ClassPass",
                category: .fitness,
                amount: Decimal(string: "39.00") ?? 39,
                billingCycle: .monthly,
                nextPaymentDate: Calendar.current.date(byAdding: .day, value: 18, to: .now) ?? .now,
                payerName: "Partner",
                source: .manual
            )
        ]

        let headphones = PurchaseRightItem(
            title: "AirPods Pro 2",
            seller: "Apple Store",
            purchaseDate: Calendar.current.date(byAdding: .day, value: -13, to: .now) ?? .now,
            returnDeadline: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
            warrantyEndDate: Calendar.current.date(byAdding: .month, value: 22, to: .now) ?? .now,
            price: Decimal(string: "279.00") ?? 279,
            category: .electronics,
            ownerName: "Ali",
            payerName: "Ali",
            notes: "Keep packaging in case of return."
        )
        headphones.checklist = [
            PurchaseChecklistTask(title: "Check cosmetic condition", sortOrder: 0),
            PurchaseChecklistTask(title: "Keep receipt handy", sortOrder: 1),
            PurchaseChecklistTask(title: "Test noise cancellation", sortOrder: 2)
        ]

        let suitcase = PurchaseRightItem(
            title: "Samsonite Cabin Case",
            seller: "Amazon",
            purchaseDate: Calendar.current.date(byAdding: .month, value: -8, to: .now) ?? .now,
            returnDeadline: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
            warrantyEndDate: Calendar.current.date(byAdding: .month, value: 16, to: .now) ?? .now,
            price: Decimal(string: "189.00") ?? 189,
            category: .travel,
            ownerName: "Partner",
            payerName: "Partner",
            notes: "Wheel wobble monitored for warranty claim."
        )
        suitcase.checklist = [
            PurchaseChecklistTask(title: "Photograph defect before claim", sortOrder: 0),
            PurchaseChecklistTask(title: "Prepare warranty terms screenshot", sortOrder: 1)
        ]

        [FamilyMember(name: "Ali", role: .owner), FamilyMember(name: "Partner", role: .adult)]
            .forEach(modelContext.insert)
        subscriptions.forEach { modelContext.insert($0) }
        modelContext.insert(headphones)
        modelContext.insert(suitcase)
    }
}
