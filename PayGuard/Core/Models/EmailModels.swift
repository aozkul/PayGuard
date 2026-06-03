//
//  EmailModels.swift
//  PayGuard
//
//  Automatic mailbox connection models for subscription discovery.
//

import Foundation
import SwiftData

enum EmailProviderKind: String, CaseIterable, Identifiable, Codable {
    case gmail
    case icloud
    case outlook
    case yahoo
    case proton
    case customIMAP

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gmail: PMLocalized("Gmail")
        case .icloud: PMLocalized("iCloud Mail")
        case .outlook: PMLocalized("Outlook / Microsoft")
        case .yahoo: PMLocalized("Yahoo Mail")
        case .proton: PMLocalized("Proton Mail Bridge")
        case .customIMAP: PMLocalized("Other IMAP account")
        }
    }

    var symbolName: String {
        switch self {
        case .gmail: "envelope.fill"
        case .icloud: "icloud.fill"
        case .outlook: "briefcase.fill"
        case .yahoo: "y.circle.fill"
        case .proton: "lock.shield.fill"
        case .customIMAP: "server.rack"
        }
    }

    var defaultHost: String {
        switch self {
        case .gmail: "imap.gmail.com"
        case .icloud: "imap.mail.me.com"
        case .outlook: "outlook.office365.com"
        case .yahoo: "imap.mail.yahoo.com"
        case .proton: "127.0.0.1"
        case .customIMAP: ""
        }
    }

    var defaultPort: Int {
        switch self {
        case .proton: 1143
        default: 993
        }
    }

    var requiresAppPasswordHint: String {
        switch self {
        case .gmail:
            return PMLocalized("Use a Google app password for IMAP access when 2-Step Verification is enabled.")
        case .icloud:
            return PMLocalized("Use an Apple app-specific password. PayGuard cannot read Apple Mail directly without this account connection.")
        case .outlook:
            return PMLocalized("Use an app password or an IMAP-enabled Microsoft mailbox. Some work tenants disable IMAP.")
        case .yahoo:
            return PMLocalized("Use a Yahoo app password for IMAP access.")
        case .proton:
            return PMLocalized("Use Proton Mail Bridge on a Mac/PC and enter the bridge IMAP settings.")
        case .customIMAP:
            return PMLocalized("Enter the IMAP host, port, username, and password from your mail provider.")
        }
    }
}

@Model
final class ConnectedEmailAccount {
    var id: UUID
    var providerRawValue: String
    var displayName: String
    var emailAddress: String
    var imapHost: String
    var imapPort: Int
    var useTLS: Bool
    var username: String
    var passwordKeychainKey: String
    var selectedScanMailbox: String
    var lastScanAt: Date?
    var lastScanStatus: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        provider: EmailProviderKind,
        displayName: String,
        emailAddress: String,
        imapHost: String,
        imapPort: Int,
        useTLS: Bool = true,
        username: String,
        passwordKeychainKey: String = "",
        selectedScanMailbox: String = "INBOX",
        lastScanAt: Date? = nil,
        lastScanStatus: String = "Not scanned yet",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerRawValue = provider.rawValue
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.useTLS = useTLS
        self.username = username
        self.passwordKeychainKey = passwordKeychainKey
        self.selectedScanMailbox = selectedScanMailbox
        self.lastScanAt = lastScanAt
        self.lastScanStatus = lastScanStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var provider: EmailProviderKind {
        get { EmailProviderKind(rawValue: providerRawValue) ?? .customIMAP }
        set { providerRawValue = newValue.rawValue }
    }
}

struct EmailScanFinding: Identifiable {
    let id = UUID()
    let accountID: UUID
    let accountLabel: String
    let subject: String
    let sender: String
    let dateText: String
    let confidence: Double
    let preview: String
    let detectedServiceName: String?
    let detectedCategory: SubscriptionCategory?
    let detectedAmountText: String?
    let detectedCurrencyCode: String?
    let detectedBillingCycle: BillingCycle?
    let detectedNextPaymentDate: Date?
    let detectedEventDate: Date?
    let payload: SmartImportPayload
}
