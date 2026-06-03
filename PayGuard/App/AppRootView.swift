//
//  AppRootView.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Combine
import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SubscriptionRecord.updatedAt, order: .reverse) private var subscriptions: [SubscriptionRecord]
    @Query(sort: \PurchaseRightItem.updatedAt, order: .reverse) private var purchases: [PurchaseRightItem]
    @Query(sort: \FamilyMember.createdAt) private var familyMembers: [FamilyMember]

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("prefersSampleData") private var prefersSampleData = false
    @AppStorage("selectedThemePreference") private var selectedThemeRaw = ThemePreference.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var selectedLanguageRaw = AppLanguage.fallback.rawValue

    @State private var router = AppRouter()
    @State private var premiumAccess = PremiumAccessController()
    @State private var splashFinished = AppStoreCaptureConfiguration.shouldSkipSplash

    private var selectedTheme: ThemePreference {
        ThemePreference(rawValue: selectedThemeRaw) ?? .system
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageRaw) ?? .fallback
    }

    private var widgetSyncToken: String {
        let subscriptionToken = subscriptions
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSince1970)-\($0.statusRawValue)-\($0.amount)"
            }
            .joined(separator: "|")
        let purchaseToken = purchases
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSince1970)-\($0.statusRawValue)-\($0.price)"
            }
            .joined(separator: "|")
        let memberToken = familyMembers
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "\($0.id.uuidString)-\($0.name)-\($0.roleRawValue)"
            }
            .joined(separator: "|")

        return [
            selectedLanguageRaw,
            premiumAccess.isLifetimeUnlocked ? "pro" : "free",
            subscriptionToken,
            purchaseToken,
            memberToken
        ].joined(separator: "||")
    }

    var body: some View {
        ZStack {
            PayGuardBackdrop()

            if splashFinished {
                if let captureScreen = AppStoreCaptureConfiguration.screen {
                    AppStoreCaptureRootView(screen: captureScreen)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if hasCompletedOnboarding {
                    MainShellView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    OnboardingFlowView(
                        onComplete: { includeSampleData in
                            prefersSampleData = includeSampleData
                            SampleDataSeeder.seedIfNeeded(
                                in: modelContext,
                                includeSampleData: includeSampleData
                            )
                            hasCompletedOnboarding = true
                            NotificationScheduler.shared.scheduleAll(
                                subscriptions: subscriptions,
                                purchases: purchases
                            )
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            } else {
                AnimatedSplashView()
                    .transition(.opacity)
                    .task {
                        SampleDataSeeder.seedIfNeeded(
                            in: modelContext,
                            includeSampleData: hasCompletedOnboarding && prefersSampleData
                        )
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.spring(response: 0.85, dampingFraction: 0.86)) {
                            splashFinished = true
                        }
                    }
            }
        }
        .environment(router)
        .environment(premiumAccess)
        .environment(\.locale, selectedLanguage.locale)
        .preferredColorScheme(selectedTheme.colorScheme)
        .task {
            premiumAccess.start()
            if AppStoreCaptureConfiguration.shouldSeedSampleData {
                SampleDataSeeder.seedIfNeeded(in: modelContext, includeSampleData: true)
            }

            if (hasCompletedOnboarding || AppStoreCaptureConfiguration.shouldSeedSampleData)
                && familyMembers.isEmpty
                && subscriptions.isEmpty
                && purchases.isEmpty {
                modelContext.insert(FamilyMember(name: "You", role: .owner))
            }
        }
        .task(id: widgetSyncToken) {
            PayGuardWidgetSnapshotStore.shared.sync(
                subscriptions: subscriptions,
                purchases: purchases,
                members: familyMembers,
                isLifetimeUnlocked: premiumAccess.isLifetimeUnlocked
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .payGuardOpenDestination)) { output in
            router.handle(userInfo: output.userInfo ?? [:])
        }
        .tint(PayGuardTheme.accent)
    }
}

enum AppStoreCaptureScreen: String {
    case onboarding
    case dashboard
    case subscriptions
    case purchases
    case settings
    case family
    case upgrade
    case video
}

enum AppStoreCaptureConfiguration {
    private static let enabledFlag = "-appstoreCapture"
    private static let screenFlag = "-appstoreScreen"
    private static let premiumUnlockKey = "premiumLifetimeUnlocked"
    private static let freeScanUsageKey = "premiumFreeScanUsageCount"
    private static let freeSmartImportUsageKey = "premiumFreeSmartImportUsageCount"

    static var shouldSkipSplash: Bool {
        screen != nil
    }

    static var shouldSeedSampleData: Bool {
        switch screen {
        case .dashboard, .subscriptions, .purchases, .settings, .family, .upgrade, .video:
            true
        case .onboarding, .none:
            false
        }
    }

    static var forcesPremiumUnlock: Bool {
        screen != nil
    }

    static var screen: AppStoreCaptureScreen? {
        guard isEnabled else { return nil }
        if let rawValue = argumentValue(after: screenFlag) ?? ProcessInfo.processInfo.environment["APPSTORE_SCREEN"],
           let configured = AppStoreCaptureScreen(rawValue: rawValue.lowercased()) {
            return configured
        }
        return .dashboard
    }

    static func prepareDefaultsIfNeeded() {
        guard let screen else { return }

        let defaults = UserDefaults.standard
        defaults.set(screen == .onboarding ? false : true, forKey: "hasCompletedOnboarding")
        defaults.set(shouldSeedSampleData, forKey: "prefersSampleData")
        defaults.set(ThemePreference.light.rawValue, forKey: "selectedThemePreference")
        defaults.set(AppLanguage.en.rawValue, forKey: AppLanguage.storageKey)
        defaults.set(forcesPremiumUnlock, forKey: premiumUnlockKey)
        defaults.set(0, forKey: freeScanUsageKey)
        defaults.set(0, forKey: freeSmartImportUsageKey)
    }

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(enabledFlag) || argumentValue(after: screenFlag) != nil
    }

    private static func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let nextIndex = arguments.index(after: index)
        guard arguments.indices.contains(nextIndex) else { return nil }
        return arguments[nextIndex]
    }
}

private struct MainShellView: View {
    @Environment(AppRouter.self) private var appRouter
    @Query(sort: \SubscriptionRecord.name) private var subscriptions: [SubscriptionRecord]
    @Query(sort: \PurchaseRightItem.title) private var purchases: [PurchaseRightItem]

    var body: some View {
        @Bindable var router = appRouter

        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.xyaxis.line")
                }
                .tag(AppTab.dashboard)

            SubscriptionListView()
                .tabItem {
                    Label("Subscriptions", systemImage: "rectangle.stack.badge.plus")
                }
                .tag(AppTab.subscriptions)

            PurchaseRightsListView()
                .tabItem {
                    Label("Warranty", systemImage: "shield.checkerboard")
                }
                .tag(AppTab.purchases)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .toolbarBackground(PayGuardTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $router.pendingDestination) { destination in
            switch destination {
            case .subscription(let id):
                if let subscription = subscriptions.first(where: { $0.id == id }) {
                    NavigationStack {
                        SubscriptionDetailView(subscription: subscription)
                    }
                } else {
                    MissingDestinationView(title: PMLocalized("Subscription not found"))
                }
            case .purchase(let id):
                if let item = purchases.first(where: { $0.id == id }) {
                    NavigationStack {
                        PurchaseRightDetailView(item: item)
                    }
                } else {
                    MissingDestinationView(title: PMLocalized("Purchase not found"))
                }
            }
        }
    }
}

private struct AppStoreCaptureRootView: View {
    let screen: AppStoreCaptureScreen

    var body: some View {
        switch screen {
        case .onboarding:
            OnboardingFlowView { _ in }
        case .dashboard:
            DashboardView()
        case .subscriptions:
            SubscriptionListView()
        case .purchases:
            PurchaseRightsListView()
        case .settings:
            SettingsView()
        case .family:
            FamilyView()
        case .upgrade:
            PremiumUpgradeSheet(gate: .advancedSummaries)
        case .video:
            AppStorePreviewShowcaseView()
        }
    }
}

private struct AppStorePreviewShowcaseView: View {
    private let scenes: [AppStoreCaptureScreen] = [.dashboard, .subscriptions, .purchases, .family, .settings]
    private let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    @State private var selectedIndex = 0

    private var activeScene: AppStoreCaptureScreen {
        scenes[selectedIndex]
    }

    private var activeCaption: String {
        switch activeScene {
        case .dashboard:
            "See the full picture"
        case .subscriptions:
            "Track every renewal"
        case .purchases:
            "Protect returns and warranty"
        case .family:
            "Keep the household organized"
        case .settings:
            "Unlock widgets and pro tools"
        case .onboarding, .upgrade, .video:
            "PayGuard"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppStoreCaptureRootView(screen: activeScene)
                .id(activeScene.rawValue)
                .transition(.opacity)

            Text(activeCaption)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.28), in: Capsule())
                .padding(.top, 72)
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.45)) {
                selectedIndex = (selectedIndex + 1) % scenes.count
            }
        }
    }
}

private struct MissingDestinationView: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(PayGuardTheme.accent)
            Text(title)
                .font(PayGuardTheme.titleFont)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PayGuardBackdrop())
    }
}

private struct AnimatedSplashView: View {
    @State private var animateRing = false
    @State private var animateGlow = false
    @State private var animateCard = false
    @State private var animateFloat = false
    @State private var animateSheen = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PayGuardTheme.midnight, PayGuardTheme.ocean, PayGuardTheme.surfaceStrong],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(PayGuardTheme.accent.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: animateGlow ? 22 : 58)
                .offset(x: -110, y: animateFloat ? -220 : -170)

            Circle()
                .fill(PayGuardTheme.sky.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: animateGlow ? 26 : 56)
                .offset(x: 150, y: animateFloat ? 240 : 190)

            Circle()
                .stroke(PayGuardTheme.accent.opacity(0.16), lineWidth: 1.5)
                .frame(width: 330, height: 330)
                .scaleEffect(animateRing ? 1.16 : 0.88)
                .opacity(animateRing ? 0.0 : 1)

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.14), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 38, style: .continuous)
                                .strokeBorder(.white.opacity(0.22), lineWidth: 1.2)
                        }
                        .frame(width: 236, height: 236)
                        .overlay(
                            RoundedRectangle(cornerRadius: 38, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.18), .clear, .white.opacity(0.08)],
                                        startPoint: animateSheen ? .topLeading : .bottomTrailing,
                                        endPoint: animateSheen ? .bottomTrailing : .topLeading
                                    )
                                )
                                .blendMode(.screen)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 38, style: .continuous)
                                .stroke(PayGuardTheme.accent.opacity(0.35), lineWidth: 2.5)
                                .scaleEffect(animateRing ? 1.08 : 0.92)
                                .opacity(animateRing ? 0 : 1)
                        }

                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 174, height: 174)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .shadow(color: .black.opacity(0.20), radius: 30, x: 0, y: 22)
                }
                .scaleEffect(animateCard ? 1 : 0.88)
                .rotationEffect(.degrees(animateCard ? 0 : -7))
                .offset(y: animateFloat ? -6 : 8)

                VStack(spacing: 10) {
                    Text("PayGuard")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("See every renewal. Protect every purchase.")
                        .font(PayGuardTheme.captionFont)
                        .foregroundStyle(.white.opacity(0.80))
                }
            }
            .padding(32)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                animateCard = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                animateRing = true
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                animateFloat = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                animateSheen = true
            }
        }
    }
}
