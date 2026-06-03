//
//  NotificationService.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class NotificationPermissionState: ObservableObject {
    @Published var status: UNAuthorizationStatus = .notDetermined

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }
}

final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let notificationSlotCount = 8

    private init() {}

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    @MainActor
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func scheduleAll(subscriptions: [SubscriptionRecord], purchases: [PurchaseRightItem]) {
        let center = UNUserNotificationCenter.current()

        subscriptions.forEach { subscription in
            replaceNotifications(for: subscription, center: center)
        }

        purchases.forEach { item in
            replaceNotifications(for: item, center: center)
        }
    }

    func removeAllPendingNotifications(center: UNUserNotificationCenter = .current()) {
        center.removeAllPendingNotificationRequests()
    }

    func replaceNotifications(for subscription: SubscriptionRecord, center: UNUserNotificationCenter = .current()) {
        let baseID = "subscription-\(subscription.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: identifiers(for: baseID, count: notificationSlotCount))

        guard !subscription.isArchived else { return }

        for (index, offset) in subscription.reminderOffsets.enumerated() {
            guard let triggerDate = scheduledTriggerDate(
                dueDate: subscription.nextPaymentDate,
                offset: offset,
                hour: subscription.reminderHour,
                minute: subscription.reminderMinute
            ),
                  triggerDate > .now else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = PMLocalized("%@ renews soon", subscription.name)
            content.body = PMLocalized(
                "%@ • %@",
                subscription.nextPaymentDate.shortRelativeDescription,
                subscription.amount.currencyString(code: subscription.currencyCode)
            )
            content.sound = .default
            content.userInfo = [
                "kind": "subscription",
                "itemID": subscription.id.uuidString
            ]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: "\(baseID)-\(index)", content: content, trigger: trigger)
            center.add(request)
        }
    }

    func replaceNotifications(for item: PurchaseRightItem, center: UNUserNotificationCenter = .current()) {
        let returnBase = "purchase-return-\(item.id.uuidString)"
        let warrantyBase = "purchase-warranty-\(item.id.uuidString)"
        center.removePendingNotificationRequests(
            withIdentifiers: identifiers(for: returnBase, count: notificationSlotCount) +
                identifiers(for: warrantyBase, count: notificationSlotCount)
        )

        guard !item.isArchived else { return }

        if item.hasReturnWindow {
            schedulePurchaseNotifications(
                center: center,
                baseID: returnBase,
                title: PMLocalized("%@ return deadline", item.title),
                dueDate: item.returnDeadline,
                detail: PMLocalized("Return window ends %@.", item.returnDeadline.shortRelativeDescription),
                offsets: item.returnReminderOffsets,
                hour: item.returnReminderHour,
                minute: item.returnReminderMinute,
                itemID: item.id
            )
        }
        if item.hasWarrantyCoverage {
            schedulePurchaseNotifications(
                center: center,
                baseID: warrantyBase,
                title: PMLocalized("%@ warranty ending", item.title),
                dueDate: item.warrantyEndDate,
                detail: PMLocalized("Warranty coverage ends %@.", item.warrantyEndDate.shortRelativeDescription),
                offsets: item.warrantyReminderOffsets,
                hour: item.warrantyReminderHour,
                minute: item.warrantyReminderMinute,
                itemID: item.id
            )
        }
    }

    private func schedulePurchaseNotifications(
        center: UNUserNotificationCenter,
        baseID: String,
        title: String,
        dueDate: Date,
        detail: String,
        offsets: [Int],
        hour: Int,
        minute: Int,
        itemID: UUID
    ) {
        for (index, offset) in offsets.enumerated() {
            guard let triggerDate = scheduledTriggerDate(
                dueDate: dueDate,
                offset: offset,
                hour: hour,
                minute: minute
            ),
                  triggerDate > .now else {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = detail
            content.sound = .default
            content.userInfo = [
                "kind": "purchase",
                "itemID": itemID.uuidString
            ]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
                repeats: false
            )
            center.add(
                UNNotificationRequest(
                    identifier: "\(baseID)-\(index)",
                    content: content,
                    trigger: trigger
                )
            )
        }
    }

    private func scheduledTriggerDate(dueDate: Date, offset: Int, hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        guard let targetDay = calendar.date(byAdding: .day, value: -offset, to: dueDate.startOfDay) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        return calendar.date(from: components)
    }

    private func identifiers(for baseID: String, count: Int) -> [String] {
        (0..<count).map { "\(baseID)-\($0)" }
    }
}
