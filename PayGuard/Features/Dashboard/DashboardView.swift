//
//  DashboardView.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(PremiumAccessController.self) private var premiumAccess
    @Query(sort: \SubscriptionRecord.nextPaymentDate) private var subscriptions: [SubscriptionRecord]
    @Query(sort: \PurchaseRightItem.returnDeadline) private var purchases: [PurchaseRightItem]
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @State private var selectedSection = 0
    @State private var selectedCategory: SubscriptionCategory?
    @State private var selectedPayer: String?
    @State private var premiumGate: PremiumGate?

    private var snapshot: DashboardSnapshot {
        BillingEngine.shared.snapshot(subscriptions: subscriptions, purchases: purchases, members: members)
    }

    private var categoryChartTotal: Decimal {
        snapshot.categoryTotals.reduce(0) { $0 + $1.total }
    }

    private var activeSubscriptions: [SubscriptionRecord] {
        subscriptions.filter { !$0.isArchived }
    }

    private var activePurchases: [PurchaseRightItem] {
        purchases.filter { !$0.isArchived }
    }

    private var nextRenewal: SubscriptionRecord? {
        snapshot.upcomingSubscriptions.first
    }

    private var leadingHouseholdBalance: HouseholdBalanceRow? {
        snapshot.householdBalances.first
    }

    private var renewalsNeedingAttention: [SubscriptionRecord] {
        activeSubscriptions
            .filter {
                guard $0.billingCycle.isRecurring else { return false }
                let days = daysUntil($0.nextPaymentDate)
                return days >= 0 && days <= 7
            }
            .sorted { $0.nextPaymentDate < $1.nextPaymentDate }
    }

    private var returnsNeedingAttention: [PurchaseRightItem] {
        activePurchases
            .filter {
                guard $0.hasReturnWindow else { return false }
                let days = daysUntil($0.returnDeadline)
                return days >= 0 && days <= 7
            }
            .sorted { $0.returnDeadline < $1.returnDeadline }
    }

    private var warrantiesNeedingAttention: [PurchaseRightItem] {
        activePurchases
            .filter {
                guard $0.hasWarrantyCoverage else { return false }
                let days = daysUntil($0.warrantyEndDate)
                return days >= 0 && days <= 30
            }
            .sorted { $0.warrantyEndDate < $1.warrantyEndDate }
    }

    private var renewalsThisWeek: Int {
        activeSubscriptions.filter {
            $0.billingCycle.isRecurring &&
                daysUntil($0.nextPaymentDate) >= 0 &&
                daysUntil($0.nextPaymentDate) <= 7
        }.count
    }

    private var returnsClosingSoon: Int {
        activePurchases.filter {
            $0.hasReturnWindow && daysUntil($0.returnDeadline) <= 7 && $0.returnDeadline >= .now.startOfDay
        }.count
    }

    private var warrantiesEndingSoon: Int {
        activePurchases.filter {
            $0.hasWarrantyCoverage && daysUntil($0.warrantyEndDate) <= 30 && $0.warrantyEndDate >= .now.startOfDay
        }.count
    }

    private var recentOneTimePurchases: [PurchaseRightItem] {
        activePurchases
            .sorted { $0.purchaseDate > $1.purchaseDate }
            .prefix(3)
            .map { $0 }
    }

    private var urgentActionCount: Int {
        renewalsThisWeek + returnsClosingSoon + warrantiesEndingSoon
    }

    private var healthLabel: String {
        switch snapshot.healthScore {
        case 85...:
            PMLocalized("Under control")
        case 70...84:
            PMLocalized("Worth reviewing")
        default:
            PMLocalized("Needs attention")
        }
    }

    private var activeCategory: SubscriptionCategory? {
        if let selectedCategory, snapshot.categoryTotals.contains(where: { $0.category == selectedCategory }) {
            return selectedCategory
        }
        return snapshot.categoryTotals.first?.category
    }

    private var activePayer: String? {
        if let selectedPayer, snapshot.memberTotals.contains(where: { $0.name == selectedPayer }) {
            return selectedPayer
        }
        return snapshot.memberTotals.first?.name
    }

    private var categoryBreakdownSubscriptions: [SubscriptionRecord] {
        guard let activeCategory else { return [] }
        return activeSubscriptions
            .filter { $0.category == activeCategory }
            .sorted { BillingEngine.shared.monthlyEquivalent(for: $0) > BillingEngine.shared.monthlyEquivalent(for: $1) }
    }

    private var payerBreakdownSubscriptions: [SubscriptionRecord] {
        guard let activePayer else { return [] }
        return activeSubscriptions
            .filter { $0.payerName == activePayer }
            .sorted { BillingEngine.shared.monthlyEquivalent(for: $0) > BillingEngine.shared.monthlyEquivalent(for: $1) }
    }

    private let breakdownGrid = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var hasAnyTrackedData: Bool {
        !activeSubscriptions.isEmpty || !activePurchases.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitleView(
                        eyebrow: "Overview",
                        title: "See what you pay, what is coming next, and what needs attention.",
                        detail: "The dashboard keeps subscriptions, return windows, and warranties in one clear place."
                    )
                    .padding(.horizontal, 20)

                    summaryCards
                    attentionCard
                    upcomingRenewalsCard
                    purchaseRightsCard
                    recentPurchasesCard

                    if premiumAccess.canUseAdvancedSummaries() {
                        actionCenterCard
                        householdBalanceCard
                        healthScoreCard
                        categoryChart
                        expensiveSubscriptionsCard
                    } else {
                        advancedSummaryTeaserCard
                    }
                }
                .padding(.vertical, 18)
            }
            .background(PayGuardBackdrop())
            .navigationTitle("Dashboard")
            .payGuardNavigationChrome()
            .sheet(item: $premiumGate) { gate in
                PremiumUpgradeSheet(gate: gate)
            }
        }
    }

    private var advancedSummaryTeaserCard: some View {
        PremiumLockedCard(
            title: "Advanced summaries",
            detail: "Unlock action recommendations, household balance, category charts, and biggest-cost breakdowns with Lifetime Pro.",
            buttonTitle: "Unlock Pro"
        ) {
            premiumGate = .advancedSummaries
        }
        .padding(.horizontal, 20)
    }

    private var summaryCards: some View {
        VStack(spacing: 16) {
            DashboardHeroMetricCard(
                eyebrow: "Monthly footprint",
                title: "Monthly cost",
                value: snapshot.monthlyTotal.currencyString(code: "EUR"),
                detail: "Your recurring spend across every active subscription.",
                footerTitle: "Active plans",
                footerValue: "\(activeSubscriptions.count)",
                systemName: "sparkles.rectangle.stack.fill",
                colors: [PayGuardTheme.ocean, PayGuardTheme.accent]
            )

            HStack(spacing: 14) {
                DashboardCompactMetricCard(
                    title: "Next charge",
                    value: nextRenewal?.nextPaymentDate.shortRelativeDescription ?? PMLocalized("None"),
                    detail: nextRenewal.map { PMLocalized("%@ • %@", $0.name, $0.amount.currencyString(code: $0.currencyCode)) } ?? PMLocalized("No scheduled payment yet"),
                    systemName: "calendar.badge.clock",
                    highlight: PayGuardTheme.accent
                )

                DashboardCompactMetricCard(
                    title: "Needs review",
                    value: "\(urgentActionCount)",
                    detail: urgentActionCount == 0 ? PMLocalized("Everything looks calm right now.") : PMLocalized("Renewals, returns, and warranties are waiting."),
                    systemName: "bell.badge.fill",
                    highlight: urgentActionCount == 0 ? PayGuardTheme.positive : PayGuardTheme.warning
                )
            }
        }
        .padding(.horizontal, 20)
    }

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What needs your attention")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text("A quick reading of the next deadlines so you know where to look first.")
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)

            if renewalsNeedingAttention.count == 1, let nextRenewalAttentionItem = renewalsNeedingAttention.first {
                NavigationLink {
                    SubscriptionDetailView(subscription: nextRenewalAttentionItem)
                } label: {
                    attentionRow(
                        title: "Renewals in the next 7 days",
                        detail: "Upcoming recurring charges that are close.",
                        value: renewalsThisWeek,
                        systemName: "repeat.circle.fill",
                        isInteractive: true
                    )
                }
                .buttonStyle(.plain)
            } else if renewalsNeedingAttention.count > 1 {
                NavigationLink {
                    AttentionSubscriptionListView(
                        title: "Renewals this week",
                        detail: PMLocalized("Review the subscriptions that are about to charge."),
                        subscriptions: renewalsNeedingAttention
                    )
                } label: {
                    attentionRow(
                        title: "Renewals in the next 7 days",
                        detail: "Upcoming recurring charges that are close.",
                        value: renewalsThisWeek,
                        systemName: "repeat.circle.fill",
                        isInteractive: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                attentionRow(
                    title: "Renewals in the next 7 days",
                    detail: "Upcoming recurring charges that are close.",
                    value: renewalsThisWeek,
                    systemName: "repeat.circle.fill"
                )
            }

            if returnsNeedingAttention.count == 1, let nextReturnAttentionItem = returnsNeedingAttention.first {
                NavigationLink {
                    PurchaseRightDetailView(item: nextReturnAttentionItem)
                } label: {
                    attentionRow(
                        title: "Return windows closing soon",
                        detail: "Products that are almost out of return coverage.",
                        value: returnsClosingSoon,
                        systemName: "arrow.uturn.backward.circle.fill",
                        isInteractive: true
                    )
                }
                .buttonStyle(.plain)
            } else if returnsNeedingAttention.count > 1 {
                NavigationLink {
                    AttentionPurchaseListView(
                        title: "Return windows closing soon",
                        detail: PMLocalized("These items are the closest to leaving their return period."),
                        items: returnsNeedingAttention,
                        mode: .returnWindow
                    )
                } label: {
                    attentionRow(
                        title: "Return windows closing soon",
                        detail: "Products that are almost out of return coverage.",
                        value: returnsClosingSoon,
                        systemName: "arrow.uturn.backward.circle.fill",
                        isInteractive: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                attentionRow(
                    title: "Return windows closing soon",
                    detail: "Products that are almost out of return coverage.",
                    value: returnsClosingSoon,
                    systemName: "arrow.uturn.backward.circle.fill"
                )
            }

            if warrantiesNeedingAttention.count == 1, let nextWarrantyAttentionItem = warrantiesNeedingAttention.first {
                NavigationLink {
                    PurchaseRightDetailView(item: nextWarrantyAttentionItem)
                } label: {
                    attentionRow(
                        title: "Warranties ending in 30 days",
                        detail: "Coverage windows that will expire soon.",
                        value: warrantiesEndingSoon,
                        systemName: "checkmark.shield.fill",
                        isInteractive: true
                    )
                }
                .buttonStyle(.plain)
            } else if warrantiesNeedingAttention.count > 1 {
                NavigationLink {
                    AttentionPurchaseListView(
                        title: "Warranties ending soon",
                        detail: PMLocalized("These coverage periods are the closest to expiring."),
                        items: warrantiesNeedingAttention,
                        mode: .warranty
                    )
                } label: {
                    attentionRow(
                        title: "Warranties ending in 30 days",
                        detail: "Coverage windows that will expire soon.",
                        value: warrantiesEndingSoon,
                        systemName: "checkmark.shield.fill",
                        isInteractive: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                attentionRow(
                    title: "Warranties ending in 30 days",
                    detail: "Coverage windows that will expire soon.",
                    value: warrantiesEndingSoon,
                    systemName: "checkmark.shield.fill"
                )
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private var healthScoreCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasAnyTrackedData {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How healthy is your setup?")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Text("This score combines duplicate services, expensive plans, and near-term renewals.")
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(PayGuardTheme.sky.opacity(0.22), lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: CGFloat(snapshot.healthScore) / 100)
                            .stroke(
                                LinearGradient(colors: [PayGuardTheme.accent, PayGuardTheme.seafoam], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text("\(snapshot.healthScore)")
                                .font(.system(.title, design: .rounded, weight: .bold))
                            Text("score")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .foregroundStyle(PayGuardTheme.textSecondary)
                        }
                    }
                    .frame(width: 96, height: 96)
                }

                PayGuardTag(title: healthLabel, accent: snapshot.healthScore >= 85 ? PayGuardTheme.positive : (snapshot.healthScore >= 70 ? PayGuardTheme.accent : PayGuardTheme.destructive))

                ForEach(snapshot.healthInsights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(PayGuardTheme.accent)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Text(insight.detail)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(PayGuardTheme.textSecondary)
                        }
                    }
                }
            } else {
                emptyState(
                    title: "No health data yet",
                    detail: "Add subscriptions or tracked purchases and PayGuard will score the overall setup."
                )
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private var actionCenterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Action center")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text("Not just reminders. These are the next decisions most likely to save money or protect coverage.")
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)

            if snapshot.actionRecommendations.isEmpty {
                Text("Nothing urgent is waiting right now. Your setup looks calm.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            } else {
                ForEach(snapshot.actionRecommendations) { action in
                    NavigationLink {
                        dashboardDestination(for: action)
                    } label: {
                        actionRecommendationRow(action)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private var householdBalanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Household balance")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Text("Compare what each person pays against the subscription value currently assigned to them.")
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)

            if let leadingHouseholdBalance, !snapshot.householdBalances.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(balanceHeadline(for: leadingHouseholdBalance))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    Text("This card is based on recurring subscriptions only, using payer versus owner assignments.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
            }

            ForEach(snapshot.householdBalances) { row in
                householdBalanceRow(row)
            }

            if snapshot.householdBalances.isEmpty {
                emptyState(
                    title: "No household balance yet",
                    detail: "Add subscriptions with owner and payer assignments to compare shared costs here."
                )
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where your subscription budget goes")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text(selectedSection == 0 ? "Compare monthly spend by service category." : "See who is paying for the recurring costs.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
                Spacer()
                Picker("Mode", selection: $selectedSection) {
                    Text("Category").tag(0)
                    Text("Payer").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if selectedSection == 0 {
                if snapshot.categoryTotals.isEmpty {
                    emptyState(
                        title: "No chart data yet",
                        detail: "Add subscriptions to see category and payer breakdowns here."
                    )
                } else {
                    categoryDonutBoard
                    categoryBreakdownCard
                }
            } else {
                if snapshot.memberTotals.isEmpty {
                    emptyState(
                        title: "No payer data yet",
                        detail: "Add subscriptions with payer details to compare who covers recurring costs."
                    )
                } else {
                    payerBreakdownBoard
                    payerBreakdownCard
                }
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private var categoryDonutBoard: some View {
        VStack(spacing: 18) {
            ZStack {
                Chart {
                    ForEach(Array(snapshot.categoryTotals.enumerated()), id: \.element.id) { index, item in
                        SectorMark(
                            angle: .value("Monthly", item.total.doubleValue),
                            innerRadius: .ratio(0.58),
                            outerRadius: .ratio(activeCategory == item.category ? 1.0 : 0.93),
                            angularInset: 4
                        )
                        .foregroundStyle(chartColor(for: index))
                        .cornerRadius(12)
                        .opacity(activeCategory == nil || activeCategory == item.category ? 1 : 0.44)
                    }
                }
                .frame(height: 300)
                .chartLegend(.hidden)

                if categoryChartTotal > 0 {
                    VStack(spacing: 6) {
                        Text(activeCategory?.label ?? PMLocalized("Monthly total"))
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textSecondary)
                        Text(selectedCategoryAmount.currencyString(code: "EUR"))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                        Text(shareLabel(for: selectedCategoryAmount, outOf: categoryChartTotal))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(PayGuardTheme.accent)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(PayGuardTheme.stroke, lineWidth: 1)
                    }
                }
            }

            LazyVGrid(columns: breakdownGrid, spacing: 12) {
                ForEach(Array(snapshot.categoryTotals.enumerated()), id: \.element.id) { index, item in
                    Button {
                        selectedCategory = item.category
                    } label: {
                        chartMetricPill(
                            color: chartColor(for: index),
                            title: item.category.label,
                            value: item.total.currencyString(code: "EUR"),
                            share: shareLabel(for: item.total, outOf: categoryChartTotal),
                            isSelected: activeCategory == item.category
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private var payerBreakdownBoard: some View {
        VStack(spacing: 18) {
            ZStack {
                Chart {
                    ForEach(Array(snapshot.memberTotals.enumerated()), id: \.element.id) { index, item in
                        SectorMark(
                            angle: .value("Monthly", item.total.doubleValue),
                            innerRadius: .ratio(0.58),
                            outerRadius: .ratio(activePayer == item.name ? 1.0 : 0.93),
                            angularInset: 4
                        )
                        .foregroundStyle(chartColor(for: index))
                        .cornerRadius(12)
                        .opacity(activePayer == nil || activePayer == item.name ? 1 : 0.44)
                    }
                }
                .frame(height: 300)
                .chartLegend(.hidden)

                if categoryChartTotal > 0 {
                    VStack(spacing: 6) {
                        Text(activePayer ?? PMLocalized("Monthly total"))
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textSecondary)
                        Text(selectedPayerAmount.currencyString(code: "EUR"))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                        Text(shareLabel(for: selectedPayerAmount, outOf: categoryChartTotal))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(PayGuardTheme.accent)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(PayGuardTheme.stroke, lineWidth: 1)
                    }
                }
            }

            LazyVGrid(columns: breakdownGrid, spacing: 12) {
                ForEach(Array(snapshot.memberTotals.enumerated()), id: \.element.id) { index, item in
                    Button {
                        selectedPayer = item.name
                    } label: {
                        chartMetricPill(
                            color: chartColor(for: index),
                            title: item.name,
                            value: item.total.currencyString(code: "EUR"),
                            share: shareLabel(for: item.total, outOf: categoryChartTotal),
                            isSelected: activePayer == item.name
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var categoryBreakdownCard: some View {
        if let activeCategory {
            breakdownCard(
                title: PMLocalized("%@ subscriptions", activeCategory.label),
                detail: PMLocalized("%d plan(s) currently sit in this category.", categoryBreakdownSubscriptions.count)
            ) {
                ForEach(categoryBreakdownSubscriptions) { item in
                    row(
                        title: item.name,
                        subtitle: "\(item.billingCycle.label) • \(item.payerName)",
                        value: BillingEngine.shared.monthlyEquivalent(for: item).currencyString(code: item.currencyCode)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var payerBreakdownCard: some View {
        if let activePayer {
            breakdownCard(
                title: PMLocalized("%@ pays for", activePayer),
                detail: PMLocalized("%d subscription(s) are billed to this person.", payerBreakdownSubscriptions.count)
            ) {
                ForEach(payerBreakdownSubscriptions) { item in
                    row(
                        title: item.name,
                        subtitle: "\(item.category.label) • \(item.nextPaymentDate.shortRelativeDescription)",
                        value: BillingEngine.shared.monthlyEquivalent(for: item).currencyString(code: item.currencyCode)
                    )
                }
            }
        }
    }

    private var upcomingRenewalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upcoming subscription charges")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if snapshot.upcomingSubscriptions.isEmpty {
                Text("No upcoming payments yet. Add your first subscription to start seeing charge timing.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            } else {
                ForEach(snapshot.upcomingSubscriptions) { item in
                    row(
                        title: item.name,
                        subtitle: "\(item.nextPaymentDate.shortRelativeDescription) • \(item.payerName)",
                        value: item.amount.currencyString(code: item.currencyCode)
                    )
                }
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private var purchaseRightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Protected purchase deadlines")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if snapshot.upcomingReturns.isEmpty && snapshot.expiringWarranties.isEmpty {
                Text("No purchase alerts yet. Add a product to watch return and warranty dates.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            } else {
                ForEach(snapshot.upcomingReturns) { item in
                    row(
                        title: item.title,
                        subtitle: PMLocalized("Return window • %@", item.returnDeadline.shortRelativeDescription),
                        value: item.price.currencyString(code: item.currencyCode)
                    )
                }
                ForEach(snapshot.expiringWarranties) { item in
                    row(
                        title: item.title,
                        subtitle: PMLocalized("Warranty • %@", item.warrantyEndDate.shortRelativeDescription),
                        value: item.price.currencyString(code: item.currencyCode)
                    )
                }
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private var recentPurchasesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent one-time purchases")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            if recentOneTimePurchases.isEmpty {
                Text("No purchases saved yet. Add receipts, invoices, or protected items to keep one-time spending visible.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            } else {
                ForEach(recentOneTimePurchases) { item in
                    NavigationLink {
                        PurchaseRightDetailView(item: item)
                    } label: {
                        row(
                            title: item.title,
                            subtitle: recentPurchaseSubtitle(for: item),
                            value: item.price.currencyString(code: item.currencyCode)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private var expensiveSubscriptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Biggest monthly costs")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            if snapshot.topSubscriptions.isEmpty {
                emptyState(
                    title: "No cost breakdown yet",
                    detail: "Add subscriptions and PayGuard will rank the biggest recurring costs here."
                )
            } else {
                ForEach(snapshot.topSubscriptions) { item in
                    row(
                        title: item.name,
                        subtitle: "\(item.category.label) • \(item.ownerName)",
                        value: BillingEngine.shared.monthlyEquivalent(for: item).currencyString(code: item.currencyCode)
                    )
                }
            }
        }
        .payGuardCardStyle()
        .padding(.horizontal, 20)
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.localizedKey)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.textPrimary)
            Text(detail.localizedKey)
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func row(title: String, subtitle: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textPrimary)
        }
    }

    private func recentPurchaseSubtitle(for item: PurchaseRightItem) -> String {
        if item.hasReturnWindow && item.hasWarrantyCoverage {
            return PMLocalized("Return + warranty tracked • %@", PayGuardFormatters.mediumDate.string(from: item.purchaseDate))
        }
        if item.hasReturnWindow {
            return PMLocalized("Return tracked • %@", item.returnDeadline.shortRelativeDescription)
        }
        if item.hasWarrantyCoverage {
            return PMLocalized("Warranty tracked • %@", item.warrantyEndDate.shortRelativeDescription)
        }
        return PMLocalized("Receipt only • %@", PayGuardFormatters.mediumDate.string(from: item.purchaseDate))
    }

    private func chartColor(for index: Int) -> LinearGradient {
        let gradients: [[Color]] = [
            [PayGuardTheme.ocean, PayGuardTheme.accent],
            [PayGuardTheme.accent, PayGuardTheme.seafoam],
            [PayGuardTheme.surfaceStrong, PayGuardTheme.ocean],
            [PayGuardTheme.sky, PayGuardTheme.ocean],
            [PayGuardTheme.seafoam, PayGuardTheme.accent]
        ]
        let colors = gradients[index % gradients.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func chartMetricPill(
        color: LinearGradient,
        title: String,
        value: String,
        share: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                Text(share)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(PayGuardTheme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? PayGuardTheme.surface : PayGuardTheme.surface.opacity(0.68))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? PayGuardTheme.accent.opacity(0.55) : PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func breakdownCard<Content: View>(title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.textPrimary)
            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(PayGuardTheme.textSecondary)
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func shareLabel(for total: Decimal, outOf overall: Decimal) -> String {
        guard overall > 0 else { return "0%" }
        let percent = Int((total.doubleValue / overall.doubleValue) * 100)
        return PMLocalized("%d%% of monthly", percent)
    }

    private var selectedCategoryAmount: Decimal {
        guard let activeCategory else { return categoryChartTotal }
        return snapshot.categoryTotals.first(where: { $0.category == activeCategory })?.total ?? categoryChartTotal
    }

    private var selectedPayerAmount: Decimal {
        guard let activePayer else { return categoryChartTotal }
        return snapshot.memberTotals.first(where: { $0.name == activePayer })?.total ?? categoryChartTotal
    }

    private func daysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: .now.startOfDay, to: date.startOfDay).day ?? 999
    }

    @ViewBuilder
    private func dashboardDestination(for action: DashboardActionRecommendation) -> some View {
        switch action.destination {
        case .subscription(let id):
            if let subscription = subscriptions.first(where: { $0.id == id }) {
                SubscriptionDetailView(subscription: subscription)
            } else {
                missingDestinationView
            }
        case .purchase(let id):
            if let item = purchases.first(where: { $0.id == id }) {
                PurchaseRightDetailView(item: item)
            } else {
                missingDestinationView
            }
        }
    }

    private var missingDestinationView: some View {
        ContentUnavailableView(
            PMLocalized("Item unavailable"),
            systemImage: "exclamationmark.triangle",
            description: Text(PMLocalized("The related item could not be found anymore."))
        )
        .background(PayGuardBackdrop())
        .payGuardNavigationChrome()
    }

    private func attentionRow(title: String, detail: String, value: Int, systemName: String, isInteractive: Bool = false) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [rowAccent(for: value).opacity(0.95), PayGuardTheme.surfaceStrong],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.pmLocalized)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(detail.pmLocalized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Text("\(value)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(value == 0 ? PayGuardTheme.textPrimary : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                value == 0
                                    ? AnyShapeStyle(PayGuardTheme.surfaceSecondary)
                                    : AnyShapeStyle(
                                        LinearGradient(
                                            colors: [rowAccent(for: value), rowAccent(for: value).opacity(0.68)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(value == 0 ? PayGuardTheme.stroke : .white.opacity(0.14), lineWidth: 1)
                    }

                if isInteractive {
                    Image(systemName: "chevron.right")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func rowAccent(for value: Int) -> Color {
        if value == 0 { return PayGuardTheme.positive }
        if value == 1 { return PayGuardTheme.warning }
        return PayGuardTheme.destructive
    }

    private func actionRecommendationRow(_ action: DashboardActionRecommendation) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(actionTint(for: action).opacity(0.16))
                Image(systemName: actionIcon(for: action))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(actionTint(for: action))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(action.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(action.actionLabel)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(actionTint(for: action))
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func householdBalanceRow(_ row: HouseholdBalanceRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(row.name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Spacer()
                Text(balanceLabel(for: row))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(balanceTone(for: row))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(balanceTone(for: row).opacity(0.14))
                    )
            }

            HStack(spacing: 12) {
                PayGuardMetricBadge(title: "Pays", value: row.paid.currencyString(code: "EUR"), accent: PayGuardTheme.accent)
                PayGuardMetricBadge(title: "Uses", value: row.owned.currencyString(code: "EUR"), accent: PayGuardTheme.seafoam)
            }

            HStack {
                Text("Difference")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                Spacer()
                Text(differenceLabel(for: row))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let total = max(row.paid.doubleValue + row.owned.doubleValue, 1)
                let paidWidth = max(24, width * CGFloat(row.paid.doubleValue / total))
                let ownedWidth = max(24, width * CGFloat(row.owned.doubleValue / total))

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(PayGuardTheme.surfaceSecondary)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PayGuardTheme.ocean, PayGuardTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: min(paidWidth, width))
                    Capsule(style: .continuous)
                        .fill(PayGuardTheme.seafoam.opacity(0.38))
                        .frame(width: min(ownedWidth, width))
                        .offset(x: min(max(width - ownedWidth, 0), width))
                }
            }
            .frame(height: 12)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func balanceHeadline(for row: HouseholdBalanceRow) -> String {
        if row.delta > 0 {
            return PMLocalized("%@ is paying more than the plans currently assigned to them.", row.name)
        }
        if row.delta < 0 {
            return PMLocalized("%@ uses more than they currently pay.", row.name)
        }
        return PMLocalized("%@ is currently balanced.", row.name)
    }

    private func balanceLabel(for row: HouseholdBalanceRow) -> String {
        if row.delta > 0 {
            return "Pays for others"
        }
        if row.delta < 0 {
            return "Others cover for them"
        }
        return "Balanced"
    }

    private func differenceLabel(for row: HouseholdBalanceRow) -> String {
        if row.delta > 0 {
            return PMLocalized("%@ more paid than used", row.delta.currencyString(code: "EUR"))
        }
        if row.delta < 0 {
            return PMLocalized("%@ more used than paid", (Decimal.zero - row.delta).currencyString(code: "EUR"))
        }
        return PMLocalized("Pays and uses are aligned")
    }

    private func balanceTone(for row: HouseholdBalanceRow) -> Color {
        if row.delta == 0 { return PayGuardTheme.positive }
        return row.delta > 0 ? PayGuardTheme.warning : PayGuardTheme.accent
    }

    private func actionTint(for action: DashboardActionRecommendation) -> Color {
        switch action.priority {
        case 0: return PayGuardTheme.destructive
        case 1: return PayGuardTheme.warning
        default: return PayGuardTheme.accent
        }
    }

    private func actionIcon(for action: DashboardActionRecommendation) -> String {
        switch action.destination {
        case .subscription:
            return "rectangle.stack.badge.play"
        case .purchase:
            return "checkmark.shield.fill"
        }
    }
}

private struct DashboardHeroMetricCard: View {
    let eyebrow: String
    let title: String
    let value: String
    let detail: String
    let footerTitle: String
    let footerValue: String
    let systemName: String
    let colors: [Color]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.pmLocalized.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.74))
                Text(title.pmLocalized)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                Text(detail.pmLocalized)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 8) {
                    Text(footerTitle.pmLocalized.uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.66))
                    Text(footerValue)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.10), in: Capsule(style: .continuous))
            }

            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 62, height: 62)
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 1)
                    .frame(width: 62, height: 62)
                Image(systemName: systemName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            colors.first ?? PayGuardTheme.ocean,
                            colors.dropFirst().first ?? PayGuardTheme.accent
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .blur(radius: 6)
                .offset(x: 42, y: 54)
        }
        .shadow(color: PayGuardTheme.shadow.opacity(0.92), radius: 26, x: 0, y: 18)
    }
}

private struct DashboardCompactMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemName: String
    let highlight: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(highlight.opacity(0.18))
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(highlight)
                }
                .frame(width: 38, height: 38)
                Spacer()
                Text(title.pmLocalized.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail.pmLocalized)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(PayGuardTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PayGuardTheme.surface.opacity(0.98),
                            PayGuardTheme.surfaceSecondary.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(highlight.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: PayGuardTheme.shadow.opacity(0.52), radius: 16, x: 0, y: 10)
    }
}

private enum AttentionPurchaseMode {
    case returnWindow
    case warranty
}

private struct AttentionSubscriptionListView: View {
    let title: String
    let detail: String
    let subscriptions: [SubscriptionRecord]

    var body: some View {
        List {
            Section {
                Text(detail)
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            .payGuardListSectionStyle()

            Section("Subscriptions") {
                ForEach(subscriptions) { subscription in
                    NavigationLink {
                        SubscriptionDetailView(subscription: subscription)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(subscription.name)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(PayGuardTheme.textPrimary)
                                Text(PMLocalized("%@ • %@", subscription.nextPaymentDate.shortRelativeDescription, subscription.payerName))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(PayGuardTheme.textSecondary)
                            }
                            Spacer()
                            Text(BillingEngine.shared.monthlyEquivalent(for: subscription).currencyString(code: subscription.currencyCode))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(PayGuardTheme.textPrimary)
                        }
                    }
                }
            }
            .payGuardListSectionStyle()
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .background(PayGuardBackdrop())
        .navigationTitle(title)
        .payGuardNavigationChrome()
    }
}

private struct AttentionPurchaseListView: View {
    let title: String
    let detail: String
    let items: [PurchaseRightItem]
    let mode: AttentionPurchaseMode

    var body: some View {
        List {
            Section {
                Text(detail)
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            .payGuardListSectionStyle()

            Section("Items") {
                ForEach(items) { item in
                    NavigationLink {
                        PurchaseRightDetailView(item: item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(PayGuardTheme.textPrimary)
                                Text(subtitle(for: item))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(PayGuardTheme.textSecondary)
                            }
                            Spacer()
                            Text(item.price.currencyString(code: item.currencyCode))
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(PayGuardTheme.textPrimary)
                        }
                    }
                }
            }
            .payGuardListSectionStyle()
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .background(PayGuardBackdrop())
        .navigationTitle(title)
        .payGuardNavigationChrome()
    }

    private func subtitle(for item: PurchaseRightItem) -> String {
        switch mode {
        case .returnWindow:
            return PMLocalized("Return window • %@", item.returnDeadline.shortRelativeDescription)
        case .warranty:
            return PMLocalized("Warranty • %@", item.warrantyEndDate.shortRelativeDescription)
        }
    }
}
