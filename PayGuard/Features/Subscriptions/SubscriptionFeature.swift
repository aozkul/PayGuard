//
//  SubscriptionFeature.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import SwiftData
import SwiftUI

struct SubscriptionListView: View {
    @Environment(PremiumAccessController.self) private var premiumAccess
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SubscriptionRecord.nextPaymentDate) private var subscriptions: [SubscriptionRecord]

    @State private var searchText = ""
    @State private var selectedBillingCycle: BillingCycle?
    @State private var selectedCategory: SubscriptionCategory?
    @State private var filterArchived = false
    @State private var editorPresentation: SubscriptionEditorPresentation?
    @State private var showingCatalog = false
    @State private var showingSmartImport = false
    @State private var showingEmailImport = false
    @State private var previewImportDraft: SubscriptionImportDraft?
    @State private var queuedPreviewEditorDraft: SubscriptionImportDraft?
    @State private var premiumGate: PremiumGate?
    @State private var pendingCatalogTemplate: ServiceTemplate?
    @State private var showingSubscriptionFilters = false
    @State private var draftBillingCycle: BillingCycle?
    @State private var draftCategory: SubscriptionCategory?
    @State private var draftFilterArchived = false
    private let catalogTemplates = ServiceCatalogLoader.loadTemplates()

    private var filteredSubscriptions: [SubscriptionRecord] {
        subscriptions.filter { item in
            let matchesArchive = filterArchived ? item.isArchived : !item.isArchived
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty || item.name.localizedCaseInsensitiveContains(query) || item.notes.localizedCaseInsensitiveContains(query)
            let matchesBillingCycle = selectedBillingCycle == nil || item.billingCycle == selectedBillingCycle
            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            return matchesArchive && matchesSearch && matchesBillingCycle && matchesCategory
        }
    }

    private var activeSubscriptions: [SubscriptionRecord] {
        subscriptions.filter { !$0.isArchived }
    }

    private var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    private var activeFilterCount: Int {
        [selectedBillingCycle != nil, selectedCategory != nil, filterArchived].filter { $0 }.count
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var monthlyTotal: Decimal {
        activeSubscriptions.reduce(into: Decimal.zero) { total, item in
            total += BillingEngine.shared.monthlyEquivalent(for: item)
        }
    }

    private var nextRecurringSubscription: SubscriptionRecord? {
        filteredSubscriptions
            .filter { !$0.isArchived && $0.billingCycle.isRecurring }
            .sorted { $0.nextPaymentDate < $1.nextPaymentDate }
            .first
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isSearching {
                        SubscriptionSearchSummaryPanel(
                            resultCount: filteredSubscriptions.count,
                            searchText: searchText
                        )
                    } else {
                        subscriptionSummaryPanel
                    }
                }
                .payGuardListSectionStyle()


                Section(filterArchived ? "Archived" : "Active subscriptions") {
                    if filteredSubscriptions.isEmpty {
                        Text(filterArchived ? "No archived subscriptions yet." : "Use the top-right action menu to add or discover subscriptions.")
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(filteredSubscriptions) { subscription in
                            NavigationLink {
                                SubscriptionDetailView(subscription: subscription)
                            } label: {
                                SubscriptionRow(subscription: subscription)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(subscription)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(PayGuardTheme.destructive)

                                Button {
                                    toggleArchive(subscription)
                                } label: {
                                    Label(subscription.isArchived ? "Restore" : "Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
                .payGuardListSectionStyle()

            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .background(PayGuardBackdrop())
            .navigationTitle("Subscriptions")
            .searchable(text: $searchText)
            .payGuardNavigationChrome()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        draftBillingCycle = selectedBillingCycle
                        draftCategory = selectedCategory
                        draftFilterArchived = filterArchived
                        showingSubscriptionFilters = true
                    } label: {
                        SubscriptionFilterToolbarIcon(isActive: hasActiveFilters)
                    }
                    .accessibilityLabel(hasActiveFilters ? "Subscription filters active" : "Subscription filters")

                    Menu {
                        Button {
                            presentManualSubscriptionEditor()
                        } label: {
                            Label("New subscription".pmLocalized, systemImage: "plus")
                        }

                        Button {
                            presentEmailImport()
                        } label: {
                            Label("Email scan".pmLocalized, systemImage: "mail.stack.fill")
                        }

                        Button {
                            presentSmartImport()
                        } label: {
                            Label("Receipt OCR".pmLocalized, systemImage: "text.viewfinder")
                        }

                        Button {
                            presentSubscriptionEditorFromCatalog()
                        } label: {
                            Label("Catalog".pmLocalized, systemImage: "sparkles")
                        }
                    } label: {
                        ToolbarCircleIcon(systemName: "plus", emphasized: true)
                    }
                    .accessibilityLabel("Subscription actions")
                }
            }
            .sheet(item: $editorPresentation) { presentation in
                NavigationStack {
                    SubscriptionEditorView(
                        template: presentation.template,
                        importDraft: presentation.importDraft
                    )
                }
            }
            .sheet(isPresented: $showingCatalog) {
                NavigationStack {
                    ServiceCatalogView { template in
                        pendingCatalogTemplate = template
                        showingCatalog = false
                    }
                }
            }
            .sheet(isPresented: $showingSmartImport) {
                SmartImportSourceSheet(
                    title: "Import from screenshot, receipt, or PDF",
                    detail: "Bring in an App Store page, renewal email, or invoice and PayGuard will prefill the subscription draft on-device."
                ) { payload in
                    previewImportDraft = SubscriptionImportDraft.make(from: payload, templates: catalogTemplates)
                }
            }
            .sheet(isPresented: $showingEmailImport) {
                EmailImportCenterView(templates: catalogTemplates) { _ in }
            }
            .sheet(item: $previewImportDraft) { draft in
                NavigationStack {
                    SubscriptionImportReviewView(draft: draft) { chosenDraft in
                        queuedPreviewEditorDraft = chosenDraft
                        previewImportDraft = nil
                    }
                }
            }
            .onChange(of: previewImportDraft?.id) { _, newValue in
                guard newValue == nil, let queuedPreviewEditorDraft else { return }
                DispatchQueue.main.async {
                    editorPresentation = SubscriptionEditorPresentation(
                        template: nil,
                        importDraft: queuedPreviewEditorDraft
                    )
                    self.queuedPreviewEditorDraft = nil
                }
            }
            .sheet(item: $premiumGate) { gate in
                PremiumUpgradeSheet(gate: gate)
            }
            .sheet(isPresented: $showingSubscriptionFilters) {
                SubscriptionFilterSheet(
                    draftBillingCycle: $draftBillingCycle,
                    draftCategory: $draftCategory,
                    draftFilterArchived: $draftFilterArchived,
                    hasAppliedFilters: hasActiveFilters,
                    onApply: {
                        selectedBillingCycle = draftBillingCycle
                        selectedCategory = draftCategory
                        filterArchived = draftFilterArchived
                        showingSubscriptionFilters = false
                    },
                    onClear: {
                        draftBillingCycle = nil
                        draftCategory = nil
                        draftFilterArchived = false
                    },
                    onCancel: {
                        draftBillingCycle = selectedBillingCycle
                        draftCategory = selectedCategory
                        draftFilterArchived = filterArchived
                        showingSubscriptionFilters = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(30)
            }
            .onChange(of: showingCatalog) { _, isPresented in
                guard !isPresented, let pendingCatalogTemplate else { return }
                self.pendingCatalogTemplate = nil
                editorPresentation = SubscriptionEditorPresentation(
                    template: pendingCatalogTemplate,
                    importDraft: nil
                )
            }
        }
    }

    private func presentManualSubscriptionEditor() {
        guard premiumAccess.canAddSubscription(activeCount: activeSubscriptions.count) else {
            premiumGate = .subscriptionLimit
            return
        }
        editorPresentation = SubscriptionEditorPresentation(
            template: nil,
            importDraft: nil
        )
    }

    private func presentEmailImport() {
        showingEmailImport = true
    }

    private func presentSmartImport() {
        guard premiumAccess.canUseDocumentScan() else {
            premiumGate = .scanLimit
            return
        }
        showingSmartImport = true
    }

    private func presentSubscriptionEditorFromCatalog() {
        guard premiumAccess.canAddSubscription(activeCount: activeSubscriptions.count) else {
            premiumGate = .subscriptionLimit
            return
        }
        showingCatalog = true
    }

    private func toggleArchive(_ subscription: SubscriptionRecord) {
        subscription.status = subscription.isArchived ? .active : .archived
        subscription.updatedAt = .now
        NotificationScheduler.shared.replaceNotifications(for: subscription)
    }

    private func delete(_ subscription: SubscriptionRecord) {
        subscription.attachments.forEach(AttachmentService.shared.delete)
        modelContext.delete(subscription)
    }

    private var subscriptionSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PayGuardTheme.ocean, PayGuardTheme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Subscriptions".localizedKey)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Keep renewals, invoices and recurring costs under control.".localizedKey)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                SubscriptionSummaryTile(
                    title: "Active",
                    value: "\(activeSubscriptions.count)",
                    symbol: "checkmark.seal.fill"
                )

                SubscriptionSummaryTile(
                    title: "Monthly",
                    value: monthlyTotal.currencyString(code: "EUR"),
                    symbol: "calendar.badge.clock"
                )
            }

            if let nextRecurringSubscription {
                NavigationLink {
                    SubscriptionDetailView(subscription: nextRecurringSubscription)
                } label: {
                    SubscriptionCompactRenewalRow(subscription: nextRecurringSubscription)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(PayGuardPremiumCardBackground(cornerRadius: 30))
    }

    private var subscriptionQuickActionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add subscription".localizedKey)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    Text("Start manually or let PayGuard discover invoices for you.".localizedKey)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                SubscriptionQuickActionButton(
                    title: "New",
                    detail: "Create manually",
                    symbol: "plus",
                    emphasized: true
                ) {
                    presentManualSubscriptionEditor()
                }

                SubscriptionQuickActionButton(
                    title: "Email scan",
                    detail: "Find invoices",
                    symbol: "mail.stack.fill"
                ) {
                    presentEmailImport()
                }

                SubscriptionQuickActionButton(
                    title: "Receipt",
                    detail: "OCR import",
                    symbol: "text.viewfinder"
                ) {
                    if premiumAccess.canUseDocumentScan() {
                        showingSmartImport = true
                    } else {
                        premiumGate = .scanLimit
                    }
                }

                SubscriptionQuickActionButton(
                    title: "Catalog",
                    detail: "Use template",
                    symbol: "sparkles"
                ) {
                    presentSubscriptionEditorFromCatalog()
                }
            }
        }
        .padding(16)
        .background(PayGuardPremiumCardBackground(cornerRadius: 28))
    }

    private var subscriptionFilterPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(filterArchived ? "Archive".localizedKey : "Active subscriptions".localizedKey, systemImage: filterArchived ? "archivebox.fill" : "tray.full.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if hasActiveFilters {
                    Button("Clear".localizedKey) {
                        selectedBillingCycle = nil
                        selectedCategory = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(PayGuardTheme.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    filterMenu(
                        title: "Cycle",
                        value: selectedBillingCycle?.label ?? PMLocalized("All"),
                        systemName: "repeat"
                    ) {
                        Button(PMLocalized("All")) {
                            selectedBillingCycle = nil
                        }
                        ForEach(BillingCycle.allCases) { cycle in
                            Button(cycle.label) {
                                selectedBillingCycle = cycle
                            }
                        }
                    }

                    filterMenu(
                        title: "Category",
                        value: selectedCategory?.label ?? PMLocalized("All"),
                        systemName: "square.grid.2x2"
                    ) {
                        Button(PMLocalized("All")) {
                            selectedCategory = nil
                        }
                        ForEach(SubscriptionCategory.allCases) { category in
                            Button(category.label) {
                                selectedCategory = category
                            }
                        }
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            filterArchived.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: filterArchived ? "tray.full.fill" : "archivebox.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(filterArchived ? "Show active" : "Archive")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(filterArchived ? PayGuardTheme.accent : PayGuardTheme.warning)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill((filterArchived ? PayGuardTheme.accent : PayGuardTheme.warning).opacity(0.12))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke((filterArchived ? PayGuardTheme.accent : PayGuardTheme.warning).opacity(0.22), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(PayGuardPremiumCardBackground(cornerRadius: 24))
    }

    private var subscriptionArchiveScopePanel: some View {
        HStack(spacing: 12) {
            Image(systemName: filterArchived ? "archivebox.fill" : "tray.full.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(filterArchived ? PayGuardTheme.warning : PayGuardTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill((filterArchived ? PayGuardTheme.warning : PayGuardTheme.accent).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(filterArchived ? "Archive view" : "Active view")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(filterArchived ? "Archived subscriptions are shown separately." : "Active subscriptions stay in the main list.")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    filterArchived.toggle()
                }
            } label: {
                Text(filterArchived ? "Show active" : "Open archive")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(filterArchived ? PayGuardTheme.textPrimary : PayGuardTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(filterArchived ? PayGuardTheme.surfaceSecondary : PayGuardTheme.accent.opacity(0.14))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(filterArchived ? PayGuardTheme.stroke : PayGuardTheme.accent.opacity(0.22), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(PayGuardPremiumCardBackground(cornerRadius: 24))
    }

    @ViewBuilder
    private func filterMenu<MenuContent: View>(
        title: String,
        value: String,
        systemName: String,
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle((title == "Category" && selectedCategory != nil) || (title == "Cycle" && selectedBillingCycle != nil) ? PayGuardTheme.accent : PayGuardTheme.textSecondary)
                Text("\(title.pmLocalized): \(value)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PayGuardTheme.surfaceSecondary)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PayGuardTheme.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}



private struct SubscriptionQuickActionButton: View {
    let title: String
    let detail: String
    let symbol: String
    var emphasized: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(emphasized ? .white : PayGuardTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(iconBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title.localizedKey)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail.localizedKey)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(emphasized ? PayGuardTheme.accent.opacity(0.12) : PayGuardTheme.surfaceSecondary.opacity(0.76))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(emphasized ? PayGuardTheme.accent.opacity(0.26) : PayGuardTheme.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var iconBackground: some ShapeStyle {
        if emphasized {
            return AnyShapeStyle(LinearGradient(colors: [PayGuardTheme.ocean, PayGuardTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(PayGuardTheme.accent.opacity(0.10))
    }
}

private struct SubscriptionEditorPresentation: Identifiable {
    let id = UUID()
    let template: ServiceTemplate?
    let importDraft: SubscriptionImportDraft?
}

private struct SubscriptionFilterToolbarIcon: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isActive ? .white : PayGuardTheme.textPrimary)
            .frame(width: 38, height: 38)
            .background(background)
            .overlay {
                Circle()
                    .stroke(isActive ? .white.opacity(0.18) : PayGuardTheme.stroke, lineWidth: 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if isActive {
                    Circle()
                        .fill(PayGuardTheme.accent)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle()
                                .stroke(PayGuardTheme.surface, lineWidth: 2)
                        }
                        .offset(x: -2, y: -2)
                        .accessibilityHidden(true)
                }
            }
            .shadow(
                color: isActive ? PayGuardTheme.accent.opacity(0.26) : PayGuardTheme.shadow.opacity(0.55),
                radius: isActive ? 14 : 10,
                x: 0,
                y: isActive ? 8 : 5
            )
    }

    @ViewBuilder
    private var background: some View {
        if isActive {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PayGuardTheme.ocean, PayGuardTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            Circle()
                .fill(PayGuardTheme.surfaceSecondary)
        }
    }
}

private struct SubscriptionFilterSheet: View {
    @Binding var draftBillingCycle: BillingCycle?
    @Binding var draftCategory: SubscriptionCategory?
    @Binding var draftFilterArchived: Bool
    let hasAppliedFilters: Bool
    let onApply: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    private var hasDraftFilters: Bool {
        draftBillingCycle != nil || draftCategory != nil || draftFilterArchived
    }

    private var selectedScopeTitle: String {
        draftFilterArchived ? "Archive".pmLocalized : "Active subscriptions".pmLocalized
    }

    private var selectedCycleTitle: String {
        draftBillingCycle?.label ?? "All".pmLocalized
    }

    private var selectedCategoryTitle: String {
        draftCategory?.label ?? "All".pmLocalized
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PayGuardBackdrop()
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    topBar

                    VStack(spacing: 12) {
                        dropdownRow(
                            title: "View".pmLocalized,
                            selectedTitle: selectedScopeTitle,
                            systemName: draftFilterArchived ? "archivebox.fill" : "tray.full.fill",
                            isActive: draftFilterArchived,
                            activeTint: draftFilterArchived ? PayGuardTheme.warning : PayGuardTheme.accent
                        ) {
                            Button {
                                draftFilterArchived = false
                            } label: {
                                Label("Active subscriptions".pmLocalized, systemImage: draftFilterArchived ? "tray" : "checkmark.circle.fill")
                            }

                            Button {
                                draftFilterArchived = true
                            } label: {
                                Label("Archive".pmLocalized, systemImage: draftFilterArchived ? "checkmark.circle.fill" : "archivebox")
                            }
                        }

                        dropdownRow(
                            title: "Billing cycle".pmLocalized,
                            selectedTitle: selectedCycleTitle,
                            systemName: "repeat",
                            isActive: draftBillingCycle != nil,
                            activeTint: PayGuardTheme.accent
                        ) {
                            Button {
                                draftBillingCycle = nil
                            } label: {
                                Label("All".pmLocalized, systemImage: draftBillingCycle == nil ? "checkmark.circle.fill" : "circle")
                            }

                            Divider()

                            ForEach(BillingCycle.allCases) { cycle in
                                Button {
                                    draftBillingCycle = cycle
                                } label: {
                                    Label(cycle.label, systemImage: draftBillingCycle == cycle ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }

                        dropdownRow(
                            title: "Category".pmLocalized,
                            selectedTitle: selectedCategoryTitle,
                            systemName: "square.grid.2x2",
                            isActive: draftCategory != nil,
                            activeTint: PayGuardTheme.accent
                        ) {
                            Button {
                                draftCategory = nil
                            } label: {
                                Label("All".pmLocalized, systemImage: draftCategory == nil ? "checkmark.circle.fill" : "circle")
                            }

                            Divider()

                            ForEach(SubscriptionCategory.allCases) { category in
                                Button {
                                    draftCategory = category
                                } label: {
                                    Label(category.label, systemImage: draftCategory == category ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(PayGuardPremiumCardBackground(cornerRadius: 28))

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Filters".pmLocalized)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 12)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(PayGuardTheme.surfaceSecondary))
                    .overlay {
                        Circle().stroke(PayGuardTheme.stroke, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close".pmLocalized)
        }
        .padding(18)
        .background(PayGuardPremiumCardBackground(cornerRadius: 28))
    }

    private func dropdownRow<Content: View>(
        title: String,
        selectedTitle: String,
        systemName: String,
        isActive: Bool,
        activeTint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(isActive ? activeTint : PayGuardTheme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill((isActive ? activeTint : PayGuardTheme.textSecondary).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.caption, design: .rounded, weight: .black))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .textCase(.uppercase)
                        .lineLimit(1)

                    Text(selectedTitle)
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isActive ? activeTint : PayGuardTheme.textSecondary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PayGuardTheme.surfaceSecondary.opacity(0.92))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isActive ? activeTint.opacity(0.32) : PayGuardTheme.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if hasDraftFilters || hasAppliedFilters {
                Button {
                    onClear()
                } label: {
                    Label("Clear filters".pmLocalized, systemImage: "xmark.circle")
                        .font(.system(.subheadline, design: .rounded, weight: .black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PayGuardTheme.destructive)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PayGuardTheme.destructive.opacity(0.10))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PayGuardTheme.destructive.opacity(0.22), lineWidth: 1)
                }
            }

            Button {
                onApply()
            } label: {
                Label("Apply".pmLocalized, systemImage: "checkmark")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [PayGuardTheme.accent, PayGuardTheme.ocean],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}

private struct SubscriptionSearchSummaryPanel: View {
    let resultCount: Int
    let searchText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(PayGuardTheme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(PMLocalized("%d subscriptions found", resultCount))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(searchText)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(14)
        .background(PayGuardPremiumCardBackground(cornerRadius: 22))
    }
}

private struct SubscriptionSummaryTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(PayGuardTheme.accent.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title.pmLocalized.uppercased())
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                Text(value.localizedKey)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PayGuardTheme.inputFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}

private struct SubscriptionCompactRenewalRow: View {
    let subscription: SubscriptionRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(PayGuardTheme.accent.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Next renewal".localizedKey)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(PMLocalized("%@ · %@", subscription.name, subscription.nextPaymentDate.shortRelativeDescription))
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Text(subscription.amount.currencyString(code: subscription.currencyCode))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textPrimary)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(PayGuardTheme.textSecondary.opacity(0.7))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PayGuardTheme.inputFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}

private struct SubscriptionRow: View {
    let subscription: SubscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PayGuardTheme.ocean.opacity(0.24), PayGuardTheme.accent.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: subscription.category.symbol)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(PayGuardTheme.accent)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text(subscription.name)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subscription.category.label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(subscription.amount.currencyString(code: subscription.currencyCode))
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(subscription.isArchived ? PayGuardTheme.textSecondary : PayGuardTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    Text(subscription.billingCycle.label)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                SubscriptionRenewalBadge(
                    title: subscription.nextPaymentDate.shortRelativeDescription,
                    systemName: "calendar.badge.clock",
                    tone: tone(for: subscription.nextPaymentDate)
                )

                if !subscription.reminderOffsets.isEmpty {
                    SubscriptionRenewalBadge(
                        title: "Alerts on",
                        systemName: "bell.fill",
                        tone: .positive
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [PayGuardTheme.surfaceSecondary.opacity(0.96), PayGuardTheme.surface.opacity(0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
        .shadow(color: PayGuardTheme.shadow.opacity(subscription.isArchived ? 0.18 : 0.34), radius: 12, x: 0, y: 8)
        .opacity(subscription.isArchived ? 0.62 : 1)
    }

    private func tone(for date: Date) -> PayGuardBadgeTone {
        let remainingDays = Calendar.current.dateComponents([.day], from: .now.startOfDay, to: date.startOfDay).day ?? 0
        if remainingDays < 0 {
            return .critical
        }
        if remainingDays <= 7 {
            return .warning
        }
        return .positive
    }
}

private struct SubscriptionRenewalBadge: View {
    let title: String
    let systemName: String
    let tone: PayGuardBadgeTone

    var body: some View {
        Label(title.localizedKey, systemImage: systemName)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tone.color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.color.opacity(0.10))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tone.color.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct SubscriptionMetaChip: View {
    enum Tone {
        case alert(PayGuardBadgeTone)
        case neutral

        var tint: Color {
            switch self {
            case .alert(let badgeTone):
                badgeTone.color
            case .neutral:
                PayGuardTheme.textSecondary
            }
        }
    }

    let title: String
    let value: String
    let tone: Tone
    let systemName: String

    init(title: String, value: String, tone: PayGuardBadgeTone, systemName: String) {
        self.title = title
        self.value = value
        self.tone = .alert(tone)
        self.systemName = systemName
    }

    init(title: String, value: String, tone: Tone, systemName: String) {
        self.title = title
        self.value = value
        self.tone = tone
        self.systemName = systemName
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tone.tint)
            Text("\(title.pmLocalized): \(value)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(tone.tint.opacity(0.10))
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(tone.tint.opacity(0.18), lineWidth: 1)
        }
    }
}

struct SubscriptionEditorView: View {
    @Environment(PremiumAccessController.self) private var premiumAccess
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SubscriptionRecord.name) private var allSubscriptions: [SubscriptionRecord]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @StateObject private var notificationState = NotificationPermissionState()

    let existingRecord: SubscriptionRecord?
    let template: ServiceTemplate?
    let importDraft: SubscriptionImportDraft?
    let onSaved: (() -> Void)?

    @State private var name = ""
    @State private var category = SubscriptionCategory.entertainment
    @State private var amountText = ""
    @State private var currencyCode = "EUR"
    @State private var billingCycle = BillingCycle.monthly
    @State private var customIntervalDays = 30
    @State private var nextPaymentDate = Date.now
    @State private var ownerName = "You"
    @State private var payerName = "You"
    @State private var notes = ""
    @State private var duplicateWarning = false
    @State private var remindersEnabled = false
    @State private var selectedReminderOffsets: Set<Int> = [7, 3, 1]
    @State private var reminderTime = Date.reminderClock(hour: 9, minute: 0)
    @State private var validationMessage: String?
    @State private var premiumGate: PremiumGate?
    @State private var pendingAttachments: [AttachmentRecord] = []
    @State private var didSave = false

    init(
        existingRecord: SubscriptionRecord? = nil,
        template: ServiceTemplate? = nil,
        importDraft: SubscriptionImportDraft? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.existingRecord = existingRecord
        self.template = template
        self.importDraft = importDraft
        self.onSaved = onSaved
    }

    var body: some View {
        ZStack {
            PayGuardBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(existingRecord == nil ? "New subscription" : "Edit subscription")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                        Text("Shape a polished record with pricing, ownership and a clean renewal schedule.")
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    PremiumEditorCard(title: "Essentials", symbol: "sparkles.rectangle.stack") {
                        PremiumTextField(title: "Name", placeholder: "Netflix, Disney+, PayGuard Pro", text: $name)
                        PremiumFieldDivider()
                        PremiumPickerField(title: "Category") {
                            Picker("Category", selection: $category) {
                                ForEach(SubscriptionCategory.allCases) { item in
                                    Text(item.label).tag(item)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        PremiumFieldDivider()
                        HStack(spacing: 12) {
                            PremiumTextField(title: "Price", placeholder: "14.99", text: $amountText)
                                .keyboardType(.decimalPad)
                            PremiumPickerField(title: "Currency") {
                                Picker("Currency", selection: $currencyCode) {
                                    ForEach(supportedCurrencies, id: \.self) { code in
                                        Text(code).tag(code)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        PremiumFieldDivider()
                        PremiumPickerField(title: "Billing cycle") {
                            VStack(spacing: 10) {
                                ForEach(BillingCycle.allCases) { item in
                                    Button {
                                        billingCycle = item
                                    } label: {
                                        BillingCycleCard(
                                            cycle: item,
                                            isSelected: billingCycle == item
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if billingCycle == .custom {
                            PremiumFieldDivider()
                            Stepper(PMLocalized("Custom interval: %d days", customIntervalDays), value: $customIntervalDays, in: 2...365)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(PayGuardTheme.textPrimary)
                        }
                        PremiumFieldDivider()
                        DatePicker(paymentDateFieldTitle, selection: $nextPaymentDate, displayedComponents: .date)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }

                    if premiumAccess.canUseFamilyManagement() {
                        PremiumEditorCard(title: "Ownership", symbol: "person.2.crop.square.stack") {
                            PremiumPickerField(title: "Owner") {
                                Picker("Owner", selection: $ownerName) {
                                    ForEach(memberNames, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            PremiumFieldDivider()
                            PremiumPickerField(title: "Payer") {
                                Picker("Payer", selection: $payerName) {
                                    ForEach(memberNames, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    } else {
                        PremiumLockedCard(
                            title: "Family management",
                            detail: "Owner and payer assignments are unlocked with Lifetime Pro.",
                            buttonTitle: "Unlock Pro"
                        ) {
                            premiumGate = .familyManagement
                        }
                    }

                    PremiumEditorCard(title: "Notes", symbol: "note.text") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(PayGuardTheme.textPrimary)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(PayGuardTheme.surfaceSecondary)
                            )
                    }

                    if existingRecord == nil {
                        PremiumEditorCard(title: "Attachments", symbol: "paperclip") {
                            AttachmentGalleryView(
                                attachments: pendingAttachments,
                                onImported: { attachment in
                                    pendingAttachments.append(attachment)
                                },
                                onDeleted: { attachment in
                                    pendingAttachments.removeAll { $0.id == attachment.id }
                                    AttachmentService.shared.delete(attachment)
                                }
                            )
                        }
                    }

                    if billingCycle.isRecurring {
                        PremiumEditorCard(title: "Renewal alerts", symbol: "bell.badge") {
                            Toggle(isOn: $remindersEnabled) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Enable subscription reminders")
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(PayGuardTheme.textPrimary)
                                    Text("Choose when PayGuard should warn you before the next charge.")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(PayGuardTheme.textSecondary)
                                }
                            }
                            .tint(PayGuardTheme.accent)

                            if remindersEnabled {
                                if !premiumAccess.supportsMultipleReminders() {
                                    PremiumFieldDivider()
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Free plan reminder limit")
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .foregroundStyle(PayGuardTheme.textPrimary)
                                        Text("Choose one reminder timing here, or unlock Pro to combine multiple alerts.")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(PayGuardTheme.textSecondary)
                                        Button("Unlock multiple reminders") {
                                            premiumGate = .multipleReminders
                                        }
                                        .buttonStyle(SecondaryActionButtonStyle())
                                    }
                                }

                                PremiumFieldDivider()
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                                    ForEach(subscriptionReminderChoices, id: \.self) { offset in
                                        Button {
                                            toggleReminder(offset)
                                        } label: {
                                            ReminderChip(
                                                title: reminderLabel(for: offset),
                                                isSelected: selectedReminderOffsets.contains(offset)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if selectedReminderOffsets.isEmpty {
                                    Text("Select at least one reminder point or turn alerts off.")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(PayGuardTheme.textSecondary)
                                }

                                PremiumFieldDivider()
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Reminder time")
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .foregroundStyle(PayGuardTheme.textPrimary)
                                        Text("Every selected alert will arrive at this hour.")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(PayGuardTheme.textSecondary)
                                    }
                                    Spacer()
                                    DatePicker(
                                        "Reminder time",
                                        selection: $reminderTime,
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                }

                                if notificationState.status != .authorized &&
                                    notificationState.status != .provisional &&
                                    notificationState.status != .ephemeral {
                                    PremiumFieldDivider()
                                    Button(notificationCTA) {
                                        handleNotificationCTA()
                                    }
                                    .buttonStyle(PrimaryActionButtonStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PayGuardTheme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    ToolbarCircleIcon(systemName: "xmark")
                }
                .accessibilityLabel("Cancel")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    ToolbarCircleIcon(systemName: "checkmark", emphasized: true)
                }
                .accessibilityLabel("Save")
            }
        }
        .task(id: formSeed) {
            populateForm()
            await notificationState.refresh()
        }
        .onChange(of: billingCycle) { _, newValue in
            guard !newValue.isRecurring else { return }
            remindersEnabled = false
            selectedReminderOffsets = [7, 3, 1]
        }
        .alert("Possible duplicate found", isPresented: $duplicateWarning) {
            Button("Review", role: .cancel) {}
            Button("Save anyway") {
                persistRecord()
            }
        } message: {
            Text("A subscription with a similar name already exists. You can review the existing item or continue anyway.")
        }
        .alert("Subscription Incomplete", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
        .sheet(item: $premiumGate) { gate in
            PremiumUpgradeSheet(gate: gate)
        }
        .onDisappear {
            cleanupUnattachedFilesIfNeeded()
        }
    }

    private var memberNames: [String] {
        let values = members.map(\.name)
        return values.isEmpty ? ["You"] : values
    }

    private var supportedCurrencies: [String] {
        ["EUR", "USD", "TRY", "GBP", "CHF", "CAD", "AUD", "NZD", "JPY", "CNY", "HKD", "SGD", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "BGN", "HRK", "RSD", "UAH", "ILS", "AED", "SAR", "QAR", "KWD", "INR", "PKR", "THB", "MYR", "IDR", "PHP", "KRW", "ZAR", "EGP", "MAD", "BRL", "MXN", "ARS", "CLP", "COP", "PEN", "RUB", "ISK", "GEL", "ALL", "BAM", "MKD"]
    }

    private func memberID(for name: String) -> UUID? {
        members.first(where: { $0.name == name })?.id
    }

    private var subscriptionReminderChoices: [Int] {
        [14, 7, 3, 1, 0]
    }

    private var notificationCTA: String {
        notificationState.status == .denied ? PMLocalized("Open notification settings") : PMLocalized("Allow notifications")
    }

    private var paymentDateFieldTitle: String {
        billingCycle == .oneTime ? PMLocalized("Payment date") : PMLocalized("Next payment")
    }

    private func reminderLabel(for offset: Int) -> String {
        if offset == 0 {
            return PMLocalized("Same day")
        }
        if offset == 1 {
            return PMLocalized("%d day before", offset)
        }
        return PMLocalized("%d days before", offset)
    }

    private func populateForm() {
        resetForm()

        if let existingRecord {
            name = existingRecord.name
            category = existingRecord.category
            amountText = "\(existingRecord.amount)"
            currencyCode = existingRecord.currencyCode
            billingCycle = existingRecord.billingCycle
            customIntervalDays = existingRecord.customIntervalDays
            nextPaymentDate = existingRecord.nextPaymentDate
            ownerName = existingRecord.ownerName
            payerName = existingRecord.payerName
            notes = existingRecord.notes
            selectedReminderOffsets = Set(existingRecord.reminderOffsets)
            remindersEnabled = existingRecord.billingCycle.isRecurring && !existingRecord.reminderOffsets.isEmpty
            reminderTime = Date.reminderClock(
                hour: existingRecord.reminderHour,
                minute: existingRecord.reminderMinute
            )
            applyFreePlanConstraints()
            return
        }

        if let importDraft {
            name = importDraft.name
            category = importDraft.category
            amountText = importDraft.amountText
            currencyCode = importDraft.currencyCode
            billingCycle = importDraft.billingCycle
            nextPaymentDate = importDraft.nextPaymentDate
            notes = importDraft.notes
            pendingAttachments = importDraft.attachments
            selectedReminderOffsets = [7, 3, 1]
            remindersEnabled = false
            reminderTime = .reminderClock(hour: 9, minute: 0)
            applyFreePlanConstraints()
            return
        }

        guard let template else { return }
        name = template.name
        category = SubscriptionCategory(rawValue: template.category) ?? .utilities
        amountText = "\(template.suggestedAmount)"
        currencyCode = template.currencyCode
        billingCycle = BillingCycle(rawValue: template.billingCycle) ?? .monthly
        notes = template.note
        selectedReminderOffsets = [7, 3, 1]
        remindersEnabled = false
        reminderTime = .reminderClock(hour: 9, minute: 0)
        applyFreePlanConstraints()
    }

    private func resetForm() {
        name = ""
        category = .entertainment
        amountText = ""
        currencyCode = "EUR"
        billingCycle = .monthly
        customIntervalDays = 30
        nextPaymentDate = .now
        ownerName = memberNames.first ?? "You"
        payerName = memberNames.first ?? "You"
        notes = ""
        pendingAttachments = []
        didSave = false
        duplicateWarning = false
        remindersEnabled = false
        selectedReminderOffsets = [7, 3, 1]
        reminderTime = .reminderClock(hour: 9, minute: 0)
        validationMessage = nil
    }

    private var formSeed: String {
        if let existingRecord {
            return "existing-\(existingRecord.id.uuidString)"
        }
        if let importDraft {
            return "import-\(importDraft.id.uuidString)"
        }
        if let template {
            return "template-\(template.id.uuidString)"
        }
        return "manual-new"
    }

    private func save() {
        let activeSubscriptionCount = allSubscriptions.filter { !$0.isArchived }.count
        if existingRecord == nil && !premiumAccess.canAddSubscription(activeCount: activeSubscriptionCount) {
            validationMessage = PMLocalized("Free includes up to %d active subscriptions. Unlock Pro to add more.", PremiumAccessController.freeSubscriptionLimit)
            return
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = PMLocalized("Please enter a subscription name.")
            return
        }
        guard normalizedDecimal(from: amountText) != nil else {
            validationMessage = PMLocalized("Please enter a valid price.")
            return
        }
        guard duplicateExists else {
            persistRecord()
            return
        }
        duplicateWarning = true
    }

    private var duplicateExists: Bool {
        allSubscriptions.contains {
            $0.id != existingRecord?.id && $0.name.normalizedLookupKey == name.normalizedLookupKey
        }
    }

    private func persistRecord() {
        guard let amount = normalizedDecimal(from: amountText) else {
            return
        }
        let reminderOffsets = (remindersEnabled && billingCycle.isRecurring) ? selectedReminderOffsets.sorted(by: >) : []
        let reminderHour = reminderTime.hourComponent
        let reminderMinute = reminderTime.minuteComponent
        let ownerMemberID = premiumAccess.canUseFamilyManagement() ? memberID(for: ownerName) : nil
        let payerMemberID = premiumAccess.canUseFamilyManagement() ? memberID(for: payerName) : nil
        let resolvedOwnerName = premiumAccess.canUseFamilyManagement() ? ownerName : "You"
        let resolvedPayerName = premiumAccess.canUseFamilyManagement() ? payerName : "You"

        let source = SubscriptionSource(rawValue: template?.source ?? existingRecord?.source.rawValue ?? importDraft?.source.rawValue ?? "manual") ?? .manual

        if let existingRecord {
            existingRecord.name = name
            existingRecord.category = category
            existingRecord.amount = amount
            existingRecord.currencyCode = currencyCode.uppercased()
            existingRecord.billingCycle = billingCycle
            existingRecord.customIntervalDays = customIntervalDays
            existingRecord.nextPaymentDate = nextPaymentDate
            existingRecord.ownerMemberID = ownerMemberID
            existingRecord.payerMemberID = payerMemberID
            existingRecord.ownerName = resolvedOwnerName
            existingRecord.payerName = resolvedPayerName
            existingRecord.notes = notes
            existingRecord.source = source
            existingRecord.reminderOffsets = reminderOffsets
            existingRecord.reminderHour = reminderHour
            existingRecord.reminderMinute = reminderMinute
            existingRecord.updatedAt = .now
            NotificationScheduler.shared.replaceNotifications(for: existingRecord)
        } else {
            let record = SubscriptionRecord(
                name: name,
                category: category,
                amount: amount,
                currencyCode: currencyCode.uppercased(),
                billingCycle: billingCycle,
                customIntervalDays: customIntervalDays,
                nextPaymentDate: nextPaymentDate,
                ownerMemberID: ownerMemberID,
                payerMemberID: payerMemberID,
                ownerName: resolvedOwnerName,
                payerName: resolvedPayerName,
                source: source,
                notes: notes,
                reminderOffsets: reminderOffsets,
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                attachments: pendingAttachments
            )
            modelContext.insert(record)
            NotificationScheduler.shared.replaceNotifications(for: record)
        }

        didSave = true
        onSaved?()
        dismiss()
    }

    private func cleanupUnattachedFilesIfNeeded() {
        guard existingRecord == nil, !didSave else { return }
        pendingAttachments.forEach(AttachmentService.shared.delete)
        pendingAttachments.removeAll()
    }

    private func toggleReminder(_ offset: Int) {
        if premiumAccess.supportsMultipleReminders() {
            if selectedReminderOffsets.contains(offset) {
                selectedReminderOffsets.remove(offset)
            } else {
                selectedReminderOffsets.insert(offset)
            }
        } else {
            if selectedReminderOffsets.contains(offset) {
                selectedReminderOffsets.remove(offset)
            } else {
                selectedReminderOffsets = [offset]
            }
        }
    }

    private func applyFreePlanConstraints() {
        guard !premiumAccess.supportsMultipleReminders() else { return }
        selectedReminderOffsets = premiumAccess.clampedOffsets(from: selectedReminderOffsets)
    }

    private func handleNotificationCTA() {
        Task {
            switch notificationState.status {
            case .denied:
                NotificationScheduler.shared.openSystemSettings()
            default:
                _ = await NotificationScheduler.shared.requestPermission()
                await notificationState.refresh()
            }
        }
    }
}

struct SubscriptionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SubscriptionRecord.name) private var allSubscriptions: [SubscriptionRecord]
    let subscription: SubscriptionRecord

    @State private var showingEdit = false

    private var monthlyEquivalent: Decimal {
        BillingEngine.shared.monthlyEquivalent(for: subscription)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SubscriptionDetailHeroCard(subscription: subscription, monthlyEquivalent: monthlyEquivalent)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    PremiumDetailMetricCard(
                        title: "Amount",
                        value: subscription.amount.currencyString(code: subscription.currencyCode),
                        symbol: "creditcard.fill"
                    )
                    PremiumDetailMetricCard(
                        title: subscription.billingCycle == .oneTime ? "Payment date" : "Next payment",
                        value: subscription.nextPaymentDate.shortRelativeDescription,
                        symbol: "calendar.badge.clock"
                    )
                    PremiumDetailMetricCard(
                        title: "Cycle",
                        value: subscription.billingCycle.label,
                        symbol: subscription.billingCycle.symbolName
                    )
                    PremiumDetailMetricCard(
                        title: "Attachments",
                        value: PMLocalized("%d file(s)", subscription.attachments.count),
                        symbol: "paperclip"
                    )
                }

                PremiumDetailPanel(title: "Details", symbol: "list.bullet.rectangle.portrait.fill") {
                    PremiumDetailKeyValueRow(title: "Category", value: subscription.category.label)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Owner", value: subscription.ownerName)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Payer", value: subscription.payerName)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Reminder offsets", value: subscription.reminderOffsets.isEmpty ? PMLocalized("Off") : subscription.reminderOffsets.reminderSummary)
                    if !subscription.reminderOffsets.isEmpty {
                        PremiumDetailDivider()
                        PremiumDetailKeyValueRow(
                            title: "Reminder time",
                            value: Date.reminderClock(
                                hour: subscription.reminderHour,
                                minute: subscription.reminderMinute
                            ).shortTimeString
                        )
                    }
                    if !subscription.notes.isEmpty {
                        PremiumDetailDivider()
                        PremiumNoteBlock(text: subscription.notes)
                    }
                }

                PremiumDetailPanel(title: "Decision support", symbol: "sparkles") {
                    VStack(spacing: 10) {
                        ForEach(Array(subscriptionInsights.enumerated()), id: \.offset) { _, insight in
                            PremiumInsightRow(title: insight.title, detail: insight.detail)
                        }
                    }
                }

                PremiumDetailPanel(title: "Lifecycle", symbol: "clock.arrow.circlepath") {
                    PremiumDetailKeyValueRow(title: "Added", value: PayGuardFormatters.mediumDate.string(from: subscription.createdAt))
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Last updated", value: PayGuardFormatters.mediumDate.string(from: subscription.updatedAt))
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Source", value: subscription.source.lifecycleLabel)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Monthly equivalent", value: monthlyEquivalent.currencyString(code: subscription.currencyCode))
                }

                PremiumDetailPanel(title: "Attachment vault", symbol: "doc.richtext.fill") {
                    AttachmentGalleryView(
                        attachments: subscription.attachments,
                        onImported: { attachment in
                            subscription.attachments.append(attachment)
                            subscription.updatedAt = .now
                        },
                        onDeleted: { attachment in
                            AttachmentService.shared.delete(attachment)
                            modelContext.delete(attachment)
                        }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(PayGuardBackdrop())
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .payGuardNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEdit = true
                } label: {
                    ToolbarCircleIcon(systemName: "square.and.pencil", emphasized: true)
                }
                .accessibilityLabel("Edit")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    subscription.status = subscription.isArchived ? .active : .archived
                    NotificationScheduler.shared.replaceNotifications(for: subscription)
                } label: {
                    ToolbarCircleIcon(systemName: subscription.isArchived ? "arrow.uturn.backward" : "archivebox")
                }
                .accessibilityLabel(subscription.isArchived ? "Restore" : "Archive")
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                SubscriptionEditorView(existingRecord: subscription)
            }
        }
    }

    private var subscriptionInsights: [(title: String, detail: String)] {
        var values: [(String, String)] = []
        let monthlyEquivalent = BillingEngine.shared.monthlyEquivalent(for: subscription)
        let duplicateCount = allSubscriptions.filter {
            $0.id != subscription.id &&
            !$0.isArchived &&
            $0.name.normalizedLookupKey == subscription.name.normalizedLookupKey
        }.count
        let days = Calendar.current.dateComponents([.day], from: .now.startOfDay, to: subscription.nextPaymentDate.startOfDay).day ?? 999

        if days >= 0 && days <= 7 {
            values.append((
                subscription.billingCycle.isRecurring ? PMLocalized("Renewal is close") : PMLocalized("Payment is close"),
                PMLocalized(
                    "%@ charges %@, so this is the right time to keep, downgrade, or archive it.",
                    subscription.name,
                    subscription.nextPaymentDate.shortRelativeDescription.lowercased()
                )
            ))
        }

        if monthlyEquivalent > Decimal(20) {
            values.append((
                PMLocalized("High-cost recurring spend"),
                PMLocalized(
                    "This plan runs about %@ per month, which makes it a strong downgrade or cancellation review candidate.",
                    monthlyEquivalent.currencyString(code: subscription.currencyCode)
                )
            ))
        }

        if duplicateCount > 0 {
            values.append((
                PMLocalized("Possible overlap"),
                PMLocalized("There are %d active records with a very similar name. Compare who uses them before the next charge lands.", duplicateCount + 1)
            ))
        }

        if subscription.ownerName != subscription.payerName {
            values.append((
                PMLocalized("Shared household plan"),
                PMLocalized(
                    "%@ is paying while %@ is marked as the owner. This is useful context when you rebalance shared costs.",
                    subscription.payerName,
                    subscription.ownerName
                )
            ))
        }

        if subscription.billingCycle.isRecurring && subscription.reminderOffsets.isEmpty {
            values.append((
                PMLocalized("No renewal alerts active"),
                PMLocalized("This subscription currently has no reminder schedule, so the next charge could arrive without warning.")
            ))
        }

        if values.isEmpty {
            values.append((
                PMLocalized("Looks healthy"),
                PMLocalized("No immediate cost, overlap, or reminder risk stands out on this subscription right now.")
            ))
        }

        return values
    }
}

private struct SubscriptionDetailHeroCard: View {
    let subscription: SubscriptionRecord
    let monthlyEquivalent: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PayGuardTheme.accent.opacity(0.28), PayGuardTheme.ocean.opacity(0.30)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: subscription.category.symbol)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(PayGuardTheme.accent)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(subscription.name)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(PayGuardTheme.textPrimary)
                                .lineLimit(2)
                            Text(subscription.category.label)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(PayGuardTheme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text((subscription.isArchived ? "Archived" : "Active").localizedKey)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(subscription.isArchived ? PayGuardTheme.warning : PayGuardTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule(style: .continuous).fill((subscription.isArchived ? PayGuardTheme.warning : PayGuardTheme.accent).opacity(0.12)))
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(subscription.amount.currencyString(code: subscription.currencyCode))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                        Text(subscription.billingCycle.label)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textSecondary)
                    }

                    Text(PMLocalized("%@ monthly equivalent", monthlyEquivalent.currencyString(code: subscription.currencyCode)))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
            }
        }
        .padding(20)
        .background(PayGuardPremiumCardBackground(cornerRadius: 30))
    }
}

private struct ReminderChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(isSelected ? .white : PayGuardTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(LinearGradient(colors: [PayGuardTheme.ocean, PayGuardTheme.accent], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(PayGuardTheme.surfaceSecondary))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? .white.opacity(0.16) : PayGuardTheme.stroke, lineWidth: 1)
            }
    }
}

private struct BillingCycleCard: View {
    let cycle: BillingCycle
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: cycle.symbolName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isSelected ? .white : PayGuardTheme.accent)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(isSelected ? .white.opacity(0.18) : PayGuardTheme.surface.opacity(0.7))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(cycle.label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : PayGuardTheme.textPrimary)

                Text(cycle.premiumDetail)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.78) : PayGuardTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? .white : PayGuardTheme.textSecondary.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isSelected
                        ? AnyShapeStyle(LinearGradient(colors: [PayGuardTheme.ocean, PayGuardTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(PayGuardTheme.surfaceSecondary)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? .white.opacity(0.18) : PayGuardTheme.stroke, lineWidth: 1)
        }
        .shadow(color: isSelected ? PayGuardTheme.accent.opacity(0.24) : .clear, radius: 18, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ServiceCatalogView: View {
    let onSelect: (ServiceTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    private let templates = ServiceCatalogLoader.loadTemplates()

    private var popularTemplates: [ServiceTemplate] {
        let featured = [
            "Netflix", "Disney+", "Spotify", "YouTube Premium",
            "ChatGPT Plus", "Notion", "Amazon Prime", "PayGuard Pro"
        ]
        return templates.filter { featured.contains($0.name) }
    }

    private var appleTemplates: [ServiceTemplate] {
        templates.filter { $0.source == SubscriptionSource.appStoreGuided.rawValue }
    }

    private var moreTemplates: [ServiceTemplate] {
        templates.filter { template in
            !popularTemplates.contains(template) && !appleTemplates.contains(template)
        }
    }

    var body: some View {
        List {
            Section {
                Text("Choose a polished template and only fill the missing details.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            .payGuardListSectionStyle()

            templateSection("Popular", templates: popularTemplates)
            templateSection("Apple services", templates: appleTemplates)
            templateSection("More templates", templates: moreTemplates)
        }
        .navigationTitle("Quick add")
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .background(PayGuardBackdrop())
        .payGuardNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    ToolbarCircleIcon(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
    }

    @ViewBuilder
    private func templateSection(_ title: String, templates: [ServiceTemplate]) -> some View {
        Section(title.localizedKey) {
            ForEach(templates) { template in
                Button {
                    onSelect(template)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                            Text(template.note)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(PayGuardTheme.textSecondary)
                        }
                        Spacer()
                        Text(template.suggestedAmount.currencyString(code: template.currencyCode))
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .payGuardListSectionStyle()
    }
}

private extension SubscriptionSource {
    var lifecycleLabel: String {
        switch self {
        case .manual:
            PMLocalized("Manual")
        case .quickAdd:
            PMLocalized("Quick add")
        case .appStoreGuided:
            PMLocalized("App Store guided")
        case .emailImport:
            PMLocalized("Email import")
        case .family:
            PMLocalized("Family")
        }
    }
}

struct SubscriptionImportDraft: Identifiable {
    let id = UUID()
    let name: String
    let category: SubscriptionCategory
    let amountText: String
    let currencyCode: String
    let billingCycle: BillingCycle
    let nextPaymentDate: Date
    let detectedBillingCycle: BillingCycle?
    let detectedNextPaymentDate: Date?
    let notes: String
    let matchedTemplate: ServiceTemplate?
    let recognizedTextPreview: String
    let source: SubscriptionSource
    let attachments: [AttachmentRecord]

    static func make(
        from payload: SmartImportPayload,
        templates: [ServiceTemplate],
        source: SubscriptionSource = .manual
    ) -> SubscriptionImportDraft {
        let matchedTemplate = bestTemplateMatch(in: payload.text, templates: templates)
        let invoiceLikeDocument = looksLikeOneTimeChargeDocument(payload.text)
        let detectedAmount = bestAmountString(in: payload.text)
        let detectedCurrencyCode = detectedCurrency(in: payload.text)
        let detectedCycle = detectedBillingCycleValue(in: payload.text) ?? (invoiceLikeDocument ? .oneTime : nil)
        let detectedNextDate = detectedRelevantDate(
            in: payload.text,
            preferFuture: detectedCycle != .oneTime && !invoiceLikeDocument
        )
        let amountText = detectedAmount ?? matchedTemplate.map { "\($0.suggestedAmount)" } ?? ""
        let currency = detectedCurrencyCode ?? matchedTemplate?.currencyCode ?? "EUR"
        let cycle = detectedCycle ?? matchedTemplate.flatMap { BillingCycle(rawValue: $0.billingCycle) } ?? .monthly
        let nextDate = detectedNextDate ?? .now
        let category = matchedTemplate.flatMap { SubscriptionCategory(rawValue: $0.category) } ?? inferredSubscriptionCategory(in: payload.text)
        let name = matchedTemplate?.name ?? inferredSubscriptionName(in: payload.text)
        let notes: String
        if source == .emailImport {
            notes = PMLocalized("Imported from email source %@ with on-device text recognition.", payload.sourceName)
        } else {
            notes = PMLocalized("Imported from %@ with on-device text recognition.", payload.sourceName)
        }

        return SubscriptionImportDraft(
            name: name,
            category: category,
            amountText: amountText,
            currencyCode: currency,
            billingCycle: cycle,
            nextPaymentDate: nextDate,
            detectedBillingCycle: detectedCycle,
            detectedNextPaymentDate: detectedNextDate,
            notes: notes,
            matchedTemplate: matchedTemplate,
            recognizedTextPreview: payload.text,
            source: source == .manual ? (matchedTemplate == nil ? .manual : .quickAdd) : source,
            attachments: payload.attachment.map { [$0] } ?? []
        )
    }

    static func make(
        from finding: EmailScanFinding,
        templates: [ServiceTemplate]
    ) -> SubscriptionImportDraft {
        let templateLookupText = [
            finding.detectedServiceName,
            finding.subject
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let matchedTemplate = bestTemplateMatch(in: templateLookupText, templates: templates)
        let fallback = make(from: finding.payload, templates: templates, source: .emailImport)
        let detectedCycle = finding.detectedBillingCycle
            ?? matchedTemplate.flatMap { BillingCycle(rawValue: $0.billingCycle) }
            ?? fallback.detectedBillingCycle
        let billingCycle = detectedCycle ?? fallback.billingCycle
        let nextPaymentDate = finding.detectedNextPaymentDate
            ?? fallback.detectedNextPaymentDate
            ?? finding.detectedEventDate
            ?? fallback.nextPaymentDate
        let name = finding.detectedServiceName ?? matchedTemplate?.name ?? fallback.name
        let category = finding.detectedCategory
            ?? matchedTemplate.flatMap { SubscriptionCategory(rawValue: $0.category) }
            ?? fallback.category
        let amountText = finding.detectedAmountText
            ?? matchedTemplate.map { canonicalAmountString(from: $0.suggestedAmount) }
            ?? fallback.amountText
        let currencyCode = finding.detectedCurrencyCode ?? matchedTemplate?.currencyCode ?? fallback.currencyCode

        return SubscriptionImportDraft(
            name: name,
            category: category,
            amountText: amountText,
            currencyCode: currencyCode,
            billingCycle: billingCycle,
            nextPaymentDate: nextPaymentDate,
            detectedBillingCycle: detectedCycle,
            detectedNextPaymentDate: finding.detectedNextPaymentDate ?? fallback.detectedNextPaymentDate,
            notes: fallback.notes,
            matchedTemplate: matchedTemplate ?? fallback.matchedTemplate,
            recognizedTextPreview: finding.payload.text,
            source: .emailImport,
            attachments: finding.payload.attachment.map { [$0] } ?? []
        )
    }
}

struct SubscriptionImportReviewView: View {
    let draft: SubscriptionImportDraft
    let onUse: (SubscriptionImportDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didUseDraft = false

    var body: some View {
        List {
            Section {
                Text("PayGuard pulled out the most likely subscription fields. You can continue into the editor and fine-tune anything before saving.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            .payGuardListSectionStyle()

            Section("Suggested fields") {
                reviewRow("Name", draft.name)
                reviewRow("Category", draft.category.label)
                reviewRow("Price", draft.amountText.isEmpty ? PMLocalized("Not detected") : PMLocalized("%@ %@", draft.amountText, draft.currencyCode))
                reviewRow("Cycle", cycleReviewValue)
                reviewRow(draft.billingCycle == .oneTime ? "Payment date" : "Next payment", nextPaymentReviewValue)
                reviewRow("Matched template", draft.matchedTemplate?.name ?? PMLocalized("None"))
            }
            .payGuardListSectionStyle()

            Section("Recognized text") {
                Text(draft.recognizedTextPreview)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .textSelection(.enabled)
            }
            .payGuardListSectionStyle()
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .background(PayGuardBackdrop())
        .navigationTitle("Import Review")
        .payGuardNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    ToolbarCircleIcon(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    didUseDraft = true
                    onUse(draft)
                } label: {
                    ToolbarCircleIcon(systemName: "arrow.right", emphasized: true)
                }
                .accessibilityLabel("Use suggestion")
            }
        }
        .onDisappear {
            cleanupUnusedDraftAttachmentsIfNeeded()
        }
    }

    private func cleanupUnusedDraftAttachmentsIfNeeded() {
        guard !didUseDraft else { return }
        draft.attachments.forEach(AttachmentService.shared.delete)
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title.localizedKey)
                .foregroundStyle(PayGuardTheme.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(.subheadline, design: .rounded))
    }

    private var cycleReviewValue: String {
        if draft.detectedBillingCycle == nil && draft.matchedTemplate == nil {
            return PMLocalized("Not detected")
        }
        return draft.billingCycle.label
    }

    private var nextPaymentReviewValue: String {
        guard let detectedNextPaymentDate = draft.detectedNextPaymentDate else {
            return PMLocalized("Not detected")
        }
        return PayGuardFormatters.mediumDate.string(from: detectedNextPaymentDate)
    }
}

private func bestTemplateMatch(in text: String, templates: [ServiceTemplate]) -> ServiceTemplate? {
    let normalizedText = text.normalizedLookupKey
    let textTokens = Set(templateLookupTokens(in: text))

    return templates
        .compactMap { template -> (ServiceTemplate, Int)? in
            let compactName = template.name.normalizedLookupKey
            let phraseMatched = normalizedText.contains(compactName)
            let significantTokens = templateLookupTokens(in: template.name)
                .filter { $0.count >= 4 }
            let tokenMatches = significantTokens.filter { token in
                textTokens.contains(token)
            }

            var score = phraseMatched ? 10 : 0
            score += tokenMatches.count * 3

            if significantTokens.count == 1, tokenMatches.count == 1 {
                score += 2
            }

            let minimumScore = phraseMatched ? 10 : (significantTokens.count <= 1 ? 5 : 6)
            guard score >= minimumScore else {
                return nil
            }

            return (template, score)
        }
        .max(by: { lhs, rhs in
            lhs.1 < rhs.1
        })?
        .0
}

private func templateLookupTokens(in text: String) -> [String] {
    text
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func inferredSubscriptionName(in text: String) -> String {
    let lines = text
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    let invoiceLikeDocument = looksLikeOneTimeChargeDocument(text)

    if let labeledTitle = labeledImportedServiceTitle(in: lines) {
        return labeledTitle
    }

    if invoiceLikeDocument,
       let serviceLine = lines.first(where: looksLikeImportedServiceTitleLine(_:)),
       let serviceName = cleanedImportedServiceTitle(from: serviceLine) {
        return serviceName
    }

    if let labeledName = labeledImportedProviderName(in: lines) {
        return labeledName
    }

    if let organizationLine = lines.first(where: looksLikeImportedProviderLine(_:)),
       let organizationName = cleanedImportedProviderName(from: organizationLine) {
        return organizationName
    }

    if let feeLine = lines.first(where: looksLikeImportedFeeLine(_:)),
       let feeName = cleanedImportedFeeName(from: feeLine) {
        return feeName
    }

    if let serviceLine = lines.first(where: looksLikeImportedServiceTitleLine(_:)),
       let serviceName = cleanedImportedServiceTitle(from: serviceLine) {
        return serviceName
    }

    return lines.first(where: { line in
        let lower = line.lowercased()
        let normalized = lower.folding(options: [.diacriticInsensitive], locale: .current)
        let blockedFragments = [
            "invoice",
            "receipt",
            "tuition invoice",
            "garanti",
            "bbva",
            "dekont",
            "receipt no",
            "transaction",
            "iban",
            "swift",
            "banka",
            "bank account",
            "duzenleyen",
            "alici",
            "belge no",
            "vergi",
            "muratpasa",
            "turkiye",
            "tarihi",
            "saati",
            "gonderim",
            "mail",
            "e-serbest",
            "ettn",
            "bilgileri",
            "bilgisi",
            "urun aciklamasi",
            "urun açıklaması",
            "sira",
            "no",
            "id household",
            "account balance",
            "payment plan",
            "amount due",
            "charges/credits",
            "academic year",
            "due date",
            "description amount",
            "one-pay"
        ]
        return line.count <= 36 &&
            line.rangeOfCharacter(from: .letters) != nil &&
            !looksLikeGenericImportedHeading(line) &&
            !blockedFragments.contains(where: { fragment in
                normalized.contains(fragment)
            }) &&
            !lower.contains("renew") &&
            !lower.contains("manage") &&
            !lower.contains("subscription")
    }) ?? PMLocalized("Imported subscription")
}

private func inferredSubscriptionCategory(in text: String) -> SubscriptionCategory {
    let lower = text.lowercased()
    if lower.contains("tuition") ||
        lower.contains("academic year") ||
        lower.contains("school") ||
        lower.contains("grade ") ||
        lower.contains("student") ||
        lower.contains("campus") ||
        lower.contains("education") ||
        lower.contains("university") ||
        lower.contains("college") ||
        lower.contains("academy") {
        return .education
    }
    if lower.contains("doctor") ||
        lower.contains("doktor") ||
        lower.contains("dr.") ||
        lower.contains(" dr ") ||
        lower.contains("clinic") ||
        lower.contains("klinik") ||
        lower.contains("hospital") ||
        lower.contains("hastane") ||
        lower.contains("medical") ||
        lower.contains("medikal") ||
        lower.contains("health") ||
        lower.contains("saglik") ||
        lower.contains("sağlık") ||
        lower.contains("muayene") ||
        lower.contains("poliklinik") ||
        lower.contains("hekim") {
        return .healthcare
    }
    if lower.contains("icloud") || lower.contains("dropbox") || lower.contains("drive") {
        return .cloud
    }
    if lower.contains("netflix") || lower.contains("spotify") || lower.contains("youtube") || lower.contains("disney") {
        return .entertainment
    }
    if lower.contains("chatgpt") || lower.contains("notion") || lower.contains("adobe") {
        return .productivity
    }
    if lower.contains("gym") || lower.contains("fitness") {
        return .fitness
    }
    if lower.contains("electric") ||
        lower.contains("electricity") ||
        lower.contains("wasser") ||
        lower.contains("water bill") ||
        lower.contains("internet") ||
        lower.contains("mobile") ||
        lower.contains("telefon") ||
        lower.contains("phone bill") ||
        lower.contains("utility bill") {
        return .utilities
    }
    if lower.contains("bank") || lower.contains("card") {
        return .finance
    }
    return .utilities
}

private func detectedBillingCycleValue(in text: String) -> BillingCycle? {
    let lower = text.lowercased()
    if lower.range(of: #"\b(one[- ]time|tek sefer|single payment)\b"#, options: .regularExpression) != nil {
        return .oneTime
    }
    if lower.range(of: #"\b(quarterly|every 3 months|per 3 months|3 months|every quarter)\b"#, options: .regularExpression) != nil {
        return .quarterly
    }
    if lower.range(of: #"\b(yearly|annual|annually|per year|every year|jährlich)\b"#, options: .regularExpression) != nil {
        return .yearly
    }
    if lower.range(of: #"\b(weekly|per week|every week)\b"#, options: .regularExpression) != nil {
        return .weekly
    }
    if lower.range(of: #"\b(monthly|per month|every month|monatlich)\b|/mo\b"#, options: .regularExpression) != nil {
        return .monthly
    }
    return nil
}

func detectedCurrency(in text: String) -> String? {
    if text.contains("€") { return "EUR" }
    if text.contains("$") { return "USD" }
    if text.contains("£") { return "GBP" }
    if text.uppercased().contains("TRY") || text.uppercased().contains("TL") || text.contains("₺") { return "TRY" }
    return nil
}

func bestAmountString(in text: String) -> String? {
    let pattern = #"(?:(?:€|\$|£|₺)\s*)?(\d{1,3}(?:[.,]\d{3})*[.,]\d{2}|\d+[.,]\d{2})(?:\s*(?:EUR|USD|GBP|TRY|TL))?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }

    let nsRange = NSRange(text.startIndex..., in: text)
    let candidates = regex.matches(in: text, range: nsRange).compactMap { match -> Decimal? in
        guard match.numberOfRanges > 1,
              let rawRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return normalizedDecimal(from: String(text[rawRange]))
    }

    guard let amount = candidates.filter({ $0 > .zero }).max() else {
        return nil
    }

    return canonicalAmountString(from: amount)
}

func detectedRelevantDate(in text: String, preferFuture: Bool) -> Date? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    let dates = matches.compactMap(\.date)

    if preferFuture {
        return dates
            .filter { $0 >= .now.startOfDay }
            .sorted()
            .first
    }

    return dates
        .filter { $0 <= .now }
        .sorted(by: >)
        .first
}

private func looksLikeOneTimeChargeDocument(_ text: String) -> Bool {
    let lower = text.lowercased()
    let invoiceKeywords = [
        "invoice",
        "receipt",
        "fatura",
        "makbuz",
        "muayene",
        "net tahsilat",
        "duzenlenme tarihi",
        "belge no",
        "serbest meslek"
    ]
    let recurringKeywords = [
        "monthly",
        "annual",
        "yearly",
        "subscription",
        "renew",
        "per month",
        "/mo",
        "abonelik",
        "yenileme"
    ]

    return invoiceKeywords.contains(where: lower.contains) &&
        !recurringKeywords.contains(where: lower.contains)
}

private func looksLikeImportedProviderLine(_ line: String) -> Bool {
    let lower = line.lowercased()
    let providerMarkers = [
        " e.v.",
        "gmbh",
        "llc",
        "ltd",
        "inc",
        "corp",
        "school",
        "academy",
        "college",
        "university",
        "institute",
        "institut",
        "campus",
        "iss ",
        "ltd.",
        "a.s.",
        "a.ş.",
        "anonim",
        "sanayi",
        "ticaret"
    ]

    return providerMarkers.contains(where: lower.contains) &&
        lower.rangeOfCharacter(from: .letters) != nil &&
        !lower.contains("invoice") &&
        !lower.contains("amount") &&
        !lower.contains("payment")
}

private func labeledImportedProviderName(in lines: [String]) -> String? {
    let inlinePatterns = [
        #"(?i)^\s*(?:merchant|seller|company|institution|provider|recipient|beneficiary|issuer|doctor|hekim|duzenleyen|düzenleyen|alici|alıcı|unvan|kurum|firma|işyeri|isyeri)\b\s*[:\-]\s*(.+)$"#,
        #"(?i)^\s*(?:merchant|seller|company|institution|provider|recipient|beneficiary|issuer|doctor|hekim|duzenleyen|düzenleyen|alici|alıcı|unvan|kurum|firma|işyeri|isyeri)\b\s+(.+)$"#
    ]

    for line in lines {
        for pattern in inlinePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: line),
                  let cleaned = cleanedImportedProviderName(from: String(line[range])) else {
                continue
            }
            return cleaned
        }
    }

    let labelOnlyPatterns = [
        #"(?i)^(merchant|seller|company|institution|provider|recipient|beneficiary|issuer|doctor|hekim|duzenleyen|düzenleyen|alici|alıcı|unvan|kurum|firma|işyeri|isyeri)$"#
    ]

    for (index, line) in lines.enumerated() where index + 1 < lines.count {
        let matchesLabel = labelOnlyPatterns.contains { pattern in
            line.range(of: pattern, options: .regularExpression) != nil
        }
        guard matchesLabel,
              let cleaned = cleanedImportedProviderName(from: lines[index + 1]) else {
            continue
        }
        return cleaned
    }

    return nil
}

private func cleanedImportedProviderName(from line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawName = trimmed
        .components(separatedBy: ",")
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let rawName else {
        return nil
    }

    let cleaned = rawName
        .replacingOccurrences(of: #"\b(?:iban|swift|bic|konto|hesap|account)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard cleaned.rangeOfCharacter(from: .letters) != nil else {
        return nil
    }

    let lower = cleaned.lowercased()
    let blockedNames = [
        "tuition invoice",
        "receipt",
        "invoice",
        "garanti bbva",
        "garanti",
        "dekont",
        "bilgileri",
        "bilgisi"
    ]
    guard !blockedNames.contains(where: lower.contains),
          !looksLikeGenericImportedHeading(cleaned) else {
        return nil
    }

    return cleaned
}

private func labeledImportedServiceTitle(in lines: [String]) -> String? {
    let labelKeys = Set([
        "ucretinneicinalindigi",
        "hizmetaciklamasi",
        "urunaciklamasi",
        "description",
        "servicedescription",
        "itemdescription"
    ])

    for (index, line) in lines.enumerated() where index + 1 < lines.count {
        let matchesLabel = labelKeys.contains(importedLookupKey(line))
        guard matchesLabel,
              let cleaned = cleanedImportedServiceTitle(from: lines[index + 1]) else {
            continue
        }
        return cleaned
    }

    return nil
}

private func looksLikeImportedServiceTitleLine(_ line: String) -> Bool {
    let lower = line.lowercased()
    let normalized = lower.folding(options: [.diacriticInsensitive], locale: .current)
    let serviceKeywords = [
        "muayene",
        "ucreti",
        "ücreti",
        "service fee",
        "membership fee",
        "course fee",
        "school fee",
        "tuition fee",
        "lesson fee",
        "consultation",
        "session",
        "therapy",
        "exam",
        "package",
        "plan"
    ]

    if serviceKeywords.contains(where: normalized.contains) {
        return true
    }

    return normalized.range(
        of: #"^\d+\s+[[:alpha:]].*?(?:[€$£₺]|\b(?:tl|try|eur|usd|gbp)\b|\d+[.,]\d{2})"#,
        options: .regularExpression
    ) != nil
}

private func cleanedImportedServiceTitle(from line: String) -> String? {
    var candidate = line
        .replacingOccurrences(of: #"(?i)^(?:urun aciklamasi|ürün açıklaması|description|service|item)\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"^\d+\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+(?:[€$£₺]?\s*\d[\d.,]*.*)$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?i)\b(?:brut|brüt|net|kdv|g\.v\.s\.|gvs)\b.*$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: ":- ").union(.whitespacesAndNewlines))

    if let separatorRange = candidate.range(of: #"(?i)\b(?:tl|try|eur|usd|gbp)\b"#, options: .regularExpression) {
        candidate = String(candidate[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard candidate.rangeOfCharacter(from: .letters) != nil,
          !looksLikeGenericImportedHeading(candidate) else {
        return nil
    }

    return candidate
}

private func looksLikeGenericImportedHeading(_ line: String) -> Bool {
    let normalized = importedLookupKey(line)

    let blockedExact = Set([
        "bilgileri",
        "bilgisi",
        "alicibilgileri",
        "alici",
        "duzenleyen",
        "ucretinneicinalindigi",
        "urunaciklamasi",
        "descriptionamount",
        "sira",
        "no",
        "kdv",
        "nettahsilat",
        "toplamtahsilat",
        "paymentplan",
        "accountbalance"
    ])

    return blockedExact.contains(normalized)
}

private func importedLookupKey(_ line: String) -> String {
    line
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(with: Locale(identifier: "tr_TR"))
        .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
        .replacingOccurrences(of: "ı", with: "i")
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .joined()
}

private func looksLikeImportedFeeLine(_ line: String) -> Bool {
    let lower = line.lowercased()
    return lower.contains("tuition fee") ||
        lower.contains("membership fee") ||
        lower.contains("course fee") ||
        lower.contains("school fee")
}

private func cleanedImportedFeeName(from line: String) -> String? {
    var candidate = line
        .replacingOccurrences(of: #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"[€$£₺]\s*\d[\d.,]*"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if let range = candidate.range(of: #"\b(?:Mr\.|Mrs\.|Ms\.|Herr|Frau)\b.*"#, options: .regularExpression) {
        candidate.removeSubrange(range)
    }

    candidate = candidate.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard candidate.rangeOfCharacter(from: .letters) != nil else {
        return nil
    }

    return candidate
}

private func normalizedDecimal(from text: String) -> Decimal? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let decimalSeparator: Character?
    if let lastComma = trimmed.lastIndex(of: ","),
       let lastDot = trimmed.lastIndex(of: ".") {
        decimalSeparator = lastComma > lastDot ? "," : "."
    } else if trimmed.contains(",") {
        decimalSeparator = ","
    } else if trimmed.contains(".") {
        decimalSeparator = "."
    } else {
        decimalSeparator = nil
    }

    let filtered = trimmed.filter { character in
        character.isNumber || character == "," || character == "."
    }
    guard !filtered.isEmpty else { return nil }

    var normalized = ""
    var didWriteDecimalSeparator = false

    for character in filtered {
        if character.isNumber {
            normalized.append(character)
        } else if let decimalSeparator, character == decimalSeparator, !didWriteDecimalSeparator {
            normalized.append(".")
            didWriteDecimalSeparator = true
        }
    }

    return Decimal(string: normalized)
}

private func canonicalAmountString(from amount: Decimal) -> String {
    NSDecimalNumber(decimal: amount).stringValue
}

private struct PremiumEditorCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title.localizedKey, systemImage: symbol)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.textPrimary)
            content
        }
        .padding(18)
        .payGuardCardStyle()
    }
}

private struct PremiumTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.pmLocalized.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textSecondary)
            TextField(placeholder.localizedKey, text: $text)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.textPrimary)
        }
    }
}

private struct PremiumPickerField<PickerContent: View>: View {
    let title: String
    @ViewBuilder let content: PickerContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.pmLocalized.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textSecondary)
            content
        }
    }
}

private struct PremiumFieldDivider: View {
    var body: some View {
        Divider()
            .overlay(PayGuardTheme.divider)
    }
}
