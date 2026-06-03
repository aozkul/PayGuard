//
//  PayGuardApp.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import SwiftData
import SwiftUI
import UserNotifications

@main
struct PayGuardApp: App {
    @UIApplicationDelegateAdaptor(PayGuardAppDelegate.self) private var appDelegate

    init() {
        AppStoreCaptureConfiguration.prepareDefaultsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [
            SubscriptionRecord.self,
            PurchaseRightItem.self,
            AttachmentRecord.self,
            PurchaseChecklistTask.self,
            FamilyMember.self,
            ConnectedEmailAccount.self
        ])
    }
}

final class PayGuardAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationCenter.default.post(
            name: .payGuardOpenDestination,
            object: nil,
            userInfo: response.notification.request.content.userInfo
        )
    }
}
