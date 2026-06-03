//
//  AppRouter.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation
import Observation

enum AppTab: Hashable {
    case dashboard
    case subscriptions
    case purchases
    case settings
}

enum PendingDestination: Identifiable {
    case subscription(UUID)
    case purchase(UUID)

    var id: String {
        switch self {
        case .subscription(let id):
            "subscription-\(id.uuidString)"
        case .purchase(let id):
            "purchase-\(id.uuidString)"
        }
    }
}

enum SettingsDeepLinkTarget: Hashable {
    case emailAccounts
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .dashboard
    var pendingDestination: PendingDestination?
    var settingsTarget: SettingsDeepLinkTarget?

    func handle(userInfo: [AnyHashable: Any]) {
        guard let kind = userInfo["kind"] as? String,
              let rawID = userInfo["itemID"] as? String,
              let id = UUID(uuidString: rawID) else {
            return
        }

        switch kind {
        case "subscription":
            selectedTab = .subscriptions
            pendingDestination = .subscription(id)
        case "purchase":
            selectedTab = .purchases
            pendingDestination = .purchase(id)
        default:
            break
        }
    }

    func openSettings(_ target: SettingsDeepLinkTarget? = nil) {
        selectedTab = .settings
        settingsTarget = target
    }
}

extension Notification.Name {
    static let payGuardOpenDestination = Notification.Name("payGuardOpenDestination")
}
