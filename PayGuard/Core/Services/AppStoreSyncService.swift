//
//  AppStoreSyncService.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation
import StoreKit

struct AppStoreEntitlement: Identifiable, Hashable {
    let id: String
    let productID: String
    let kind: String
    let expirationDate: Date?

    var statusLabel: String {
        if let expirationDate {
            return PMLocalized("Expires %@", PayGuardFormatters.mediumDate.string(from: expirationDate))
        }
        return PMLocalized("Active")
    }
}

enum AppStoreSyncService {
    static func syncOwnPurchases() async throws -> [AppStoreEntitlement] {
        try await AppStore.sync()
        return try await currentEntitlements()
    }

    static func currentEntitlements() async throws -> [AppStoreEntitlement] {
        var entitlements: [AppStoreEntitlement] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            entitlements.append(
                AppStoreEntitlement(
                    id: transaction.productID,
                    productID: transaction.productID,
                    kind: label(for: transaction.productType),
                    expirationDate: transaction.expirationDate
                )
            )
        }

        return entitlements.sorted { $0.productID < $1.productID }
    }

    private static func label(for type: Product.ProductType) -> String {
        switch type {
        case .autoRenewable:
            PMLocalized("Auto-renewable")
        case .nonRenewable:
            PMLocalized("Non-renewing")
        case .consumable:
            PMLocalized("Consumable")
        case .nonConsumable:
            PMLocalized("Non-consumable")
        default:
            PMLocalized("Purchase")
        }
    }
}
