//
//  AppModels.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation
import SwiftData

enum BillingCycle: String, CaseIterable, Identifiable {
    case oneTime
    case weekly
    case monthly
    case quarterly
    case yearly
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneTime: PMLocalized("One-time")
        case .weekly: PMLocalized("Weekly")
        case .monthly: PMLocalized("Monthly")
        case .quarterly: PMLocalized("Quarterly")
        case .yearly: PMLocalized("Yearly")
        case .custom: PMLocalized("Custom")
        }
    }

    var symbolName: String {
        switch self {
        case .oneTime: "sparkles"
        case .weekly: "calendar.badge.clock"
        case .monthly: "calendar"
        case .quarterly: "calendar.badge.plus"
        case .yearly: "calendar.circle"
        case .custom: "slider.horizontal.3"
        }
    }

    var premiumDetail: String {
        switch self {
        case .oneTime: PMLocalized("Single charge")
        case .weekly: PMLocalized("Every 7 days")
        case .monthly: PMLocalized("Every month")
        case .quarterly: PMLocalized("Every 3 months")
        case .yearly: PMLocalized("Every year")
        case .custom: PMLocalized("Flexible interval")
        }
    }

    var isRecurring: Bool {
        self != .oneTime
    }
}

enum SubscriptionCategory: String, CaseIterable, Identifiable {
    case entertainment
    case productivity
    case fitness
    case cloud
    case education
    case healthcare
    case utilities
    case finance
    case lifestyle

    var id: String { rawValue }

    var label: String {
        PMLocalized(rawValue.capitalized)
    }

    var symbol: String {
        switch self {
        case .entertainment: "play.tv"
        case .productivity: "sparkles.rectangle.stack"
        case .fitness: "figure.run"
        case .cloud: "icloud"
        case .education: "book.closed"
        case .healthcare: "cross.case"
        case .utilities: "wrench.and.screwdriver"
        case .finance: "creditcard"
        case .lifestyle: "bag"
        }
    }
}

enum SubscriptionSource: String, CaseIterable, Identifiable {
    case manual
    case quickAdd
    case appStoreGuided
    case emailImport
    case family

    var id: String { rawValue }
}

enum RecordStatus: String, CaseIterable, Identifiable {
    case active
    case archived

    var id: String { rawValue }
}

enum MemberRole: String, CaseIterable, Identifiable {
    case owner
    case adult
    case child
    case guest

    var id: String { rawValue }

    var label: String {
        PMLocalized(rawValue.capitalized)
    }
}

enum PurchaseCategory: String, CaseIterable, Identifiable {
    case electronics
    case home
    case fashion
    case travel
    case gaming
    case appliances
    case general

    var id: String { rawValue }

    var label: String {
        PMLocalized(rawValue.capitalized)
    }
}

@Model
final class FamilyMember {
    var id: UUID
    var name: String
    var roleRawValue: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        role: MemberRole,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.roleRawValue = role.rawValue
        self.createdAt = createdAt
    }

    var role: MemberRole {
        get { MemberRole(rawValue: roleRawValue) ?? .adult }
        set { roleRawValue = newValue.rawValue }
    }
}

@Model
final class SubscriptionRecord {
    var id: UUID
    var name: String
    var categoryRawValue: String
    var amount: Decimal
    var currencyCode: String
    var billingCycleRawValue: String
    var customIntervalDays: Int
    var nextPaymentDate: Date
    var trialEndDate: Date?
    var ownerMemberID: UUID?
    var payerMemberID: UUID?
    var ownerName: String
    var payerName: String
    var sourceRawValue: String
    var notes: String
    var statusRawValue: String
    var reminderOffsetsCSV: String
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \AttachmentRecord.subscription)
    var attachments: [AttachmentRecord]

    init(
        id: UUID = UUID(),
        name: String,
        category: SubscriptionCategory,
        amount: Decimal,
        currencyCode: String = "EUR",
        billingCycle: BillingCycle,
        customIntervalDays: Int = 30,
        nextPaymentDate: Date,
        trialEndDate: Date? = nil,
        ownerMemberID: UUID? = nil,
        payerMemberID: UUID? = nil,
        ownerName: String = "You",
        payerName: String = "You",
        source: SubscriptionSource = .manual,
        notes: String = "",
        status: RecordStatus = .active,
        reminderOffsets: [Int] = [7, 3, 1],
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        attachments: [AttachmentRecord] = []
    ) {
        self.id = id
        self.name = name
        self.categoryRawValue = category.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.billingCycleRawValue = billingCycle.rawValue
        self.customIntervalDays = customIntervalDays
        self.nextPaymentDate = nextPaymentDate
        self.trialEndDate = trialEndDate
        self.ownerMemberID = ownerMemberID
        self.payerMemberID = payerMemberID
        self.ownerName = ownerName
        self.payerName = payerName
        self.sourceRawValue = source.rawValue
        self.notes = notes
        self.statusRawValue = status.rawValue
        self.reminderOffsetsCSV = reminderOffsets.map(String.init).joined(separator: ",")
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachments = attachments
    }

    var category: SubscriptionCategory {
        get { SubscriptionCategory(rawValue: categoryRawValue) ?? .utilities }
        set { categoryRawValue = newValue.rawValue }
    }

    var billingCycle: BillingCycle {
        get { BillingCycle(rawValue: billingCycleRawValue) ?? .monthly }
        set { billingCycleRawValue = newValue.rawValue }
    }

    var source: SubscriptionSource {
        get { SubscriptionSource(rawValue: sourceRawValue) ?? .manual }
        set { sourceRawValue = newValue.rawValue }
    }

    var status: RecordStatus {
        get { RecordStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    var reminderOffsets: [Int] {
        get {
            reminderOffsetsCSV
                .split(separator: ",")
                .compactMap { Int($0) }
        }
        set {
            reminderOffsetsCSV = newValue.map(String.init).joined(separator: ",")
        }
    }

    var isArchived: Bool {
        status == .archived
    }

    func refreshNextPayment() {
        nextPaymentDate = BillingEngine.shared.nextPaymentDate(
            from: nextPaymentDate,
            cycle: billingCycle,
            customIntervalDays: customIntervalDays
        )
        updatedAt = .now
    }
}

@Model
final class PurchaseRightItem {
    var id: UUID
    var title: String
    var seller: String
    var purchaseDate: Date
    var hasReturnWindow: Bool = true
    var hasWarrantyCoverage: Bool = true
    var returnDeadline: Date
    var warrantyEndDate: Date
    var price: Decimal
    var currencyCode: String
    var categoryRawValue: String
    var ownerMemberID: UUID?
    var payerMemberID: UUID?
    var ownerName: String
    var payerName: String
    var notes: String
    var statusRawValue: String
    var reminderOffsetsCSV: String
    var warrantyReminderOffsetsCSV: String
    var returnReminderHour: Int = 9
    var returnReminderMinute: Int = 0
    var warrantyReminderHour: Int = 9
    var warrantyReminderMinute: Int = 0
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \AttachmentRecord.purchase)
    var attachments: [AttachmentRecord]
    @Relationship(deleteRule: .cascade, inverse: \PurchaseChecklistTask.purchase)
    var checklist: [PurchaseChecklistTask]

    init(
        id: UUID = UUID(),
        title: String,
        seller: String,
        purchaseDate: Date,
        hasReturnWindow: Bool = true,
        hasWarrantyCoverage: Bool = true,
        returnDeadline: Date,
        warrantyEndDate: Date,
        price: Decimal,
        currencyCode: String = "EUR",
        category: PurchaseCategory = .general,
        ownerMemberID: UUID? = nil,
        payerMemberID: UUID? = nil,
        ownerName: String = "You",
        payerName: String = "You",
        notes: String = "",
        status: RecordStatus = .active,
        returnReminderOffsets: [Int] = [7, 3, 1],
        warrantyReminderOffsets: [Int] = [30, 7],
        returnReminderHour: Int = 9,
        returnReminderMinute: Int = 0,
        warrantyReminderHour: Int = 9,
        warrantyReminderMinute: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        attachments: [AttachmentRecord] = [],
        checklist: [PurchaseChecklistTask] = []
    ) {
        self.id = id
        self.title = title
        self.seller = seller
        self.purchaseDate = purchaseDate
        self.hasReturnWindow = hasReturnWindow
        self.hasWarrantyCoverage = hasWarrantyCoverage
        self.returnDeadline = returnDeadline
        self.warrantyEndDate = warrantyEndDate
        self.price = price
        self.currencyCode = currencyCode
        self.categoryRawValue = category.rawValue
        self.ownerMemberID = ownerMemberID
        self.payerMemberID = payerMemberID
        self.ownerName = ownerName
        self.payerName = payerName
        self.notes = notes
        self.statusRawValue = status.rawValue
        self.reminderOffsetsCSV = returnReminderOffsets.map(String.init).joined(separator: ",")
        self.warrantyReminderOffsetsCSV = warrantyReminderOffsets.map(String.init).joined(separator: ",")
        self.returnReminderHour = returnReminderHour
        self.returnReminderMinute = returnReminderMinute
        self.warrantyReminderHour = warrantyReminderHour
        self.warrantyReminderMinute = warrantyReminderMinute
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachments = attachments
        self.checklist = checklist
    }

    var category: PurchaseCategory {
        get { PurchaseCategory(rawValue: categoryRawValue) ?? .general }
        set { categoryRawValue = newValue.rawValue }
    }

    var status: RecordStatus {
        get { RecordStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    var returnReminderOffsets: [Int] {
        get {
            reminderOffsetsCSV
                .split(separator: ",")
                .compactMap { Int($0) }
        }
        set {
            reminderOffsetsCSV = newValue.map(String.init).joined(separator: ",")
        }
    }

    var warrantyReminderOffsets: [Int] {
        get {
            warrantyReminderOffsetsCSV
                .split(separator: ",")
                .compactMap { Int($0) }
        }
        set {
            warrantyReminderOffsetsCSV = newValue.map(String.init).joined(separator: ",")
        }
    }

    var isArchived: Bool {
        status == .archived
    }

    var trackedReturnDeadline: Date? {
        hasReturnWindow ? returnDeadline : nil
    }

    var trackedWarrantyEndDate: Date? {
        hasWarrantyCoverage ? warrantyEndDate : nil
    }

    var nextProtectionDate: Date? {
        [trackedReturnDeadline, trackedWarrantyEndDate].compactMap { $0 }.min()
    }

    var hasAnyProtection: Bool {
        hasReturnWindow || hasWarrantyCoverage
    }
}

@Model
final class PurchaseChecklistTask {
    var id: UUID
    var title: String
    var isDone: Bool
    var note: String
    var sortOrder: Int
    var purchase: PurchaseRightItem?

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        note: String = "",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.note = note
        self.sortOrder = sortOrder
    }
}

@Model
final class AttachmentRecord {
    var id: UUID
    var fileName: String
    var fileType: String
    var createdAt: Date
    var relativePath: String
    var subscription: SubscriptionRecord?
    var purchase: PurchaseRightItem?

    init(
        id: UUID = UUID(),
        fileName: String,
        fileType: String,
        createdAt: Date = .now,
        relativePath: String
    ) {
        self.id = id
        self.fileName = fileName
        self.fileType = fileType
        self.createdAt = createdAt
        self.relativePath = relativePath
    }
}

struct ServiceTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let category: String
    let suggestedAmount: Decimal
    let currencyCode: String
    let billingCycle: String
    let note: String
    let source: String
}
