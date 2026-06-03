//
//  AppStoreImportAdvisor.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation

struct AppStoreImportAdvice {
    let canDirectlyImport: Bool
    let headline: String
    let detail: String
    let primaryActionTitle: String
    let supportedAutomationDetail: String
}

enum AppStoreImportAdvisor {
    static func advice() -> AppStoreImportAdvice {
        AppStoreImportAdvice(
            canDirectlyImport: false,
            headline: PMLocalized("Apple does not expose every App Store subscription to third-party apps."),
            detail: PMLocalized("PayGuard can guide you with Apple service templates and review checklists, but it cannot read the full Subscriptions screen from iOS Settings for other apps. This keeps the experience honest and App Review-friendly."),
            primaryActionTitle: PMLocalized("Use guided quick add"),
            supportedAutomationDetail: PMLocalized("What PayGuard can sync automatically is its own StoreKit purchases and entitlements when you explicitly trigger App Store sync.")
        )
    }
}
