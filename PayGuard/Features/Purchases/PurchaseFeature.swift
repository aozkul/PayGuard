//
//  PurchaseFeature.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import SwiftData
import SwiftUI
import UIKit

struct PurchaseRightsListView: View {
    @Environment(PremiumAccessController.self) private var premiumAccess
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PurchaseRightItem.returnDeadline) private var items: [PurchaseRightItem]

    @State private var searchText = ""
    @State private var showingSmartImport = false
    @State private var editorPresentation: PurchaseEditorPresentation?
    @State private var previewImportDraft: PurchaseImportDraft?
    @State private var queuedImportDraft: PurchaseImportDraft?
    @State private var premiumGate: PremiumGate?

    private var filteredItems: [PurchaseRightItem] {
        activeItems.filter { item in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty ||
                item.title.localizedCaseInsensitiveContains(query) ||
                item.seller.localizedCaseInsensitiveContains(query) ||
                item.notes.localizedCaseInsensitiveContains(query)

            guard matchesSearch else { return false }

            return true
        }
        .sorted { lhs, rhs in
            nearestRelevantDate(for: lhs) < nearestRelevantDate(for: rhs)
        }
    }

    private var activeItems: [PurchaseRightItem] {
        items.filter { !$0.isArchived }
    }

    private var needsActionItems: [PurchaseRightItem] {
        activeItems
            .filter(isNeedingAttention)
            .sorted { nearestRelevantDate(for: $0) < nearestRelevantDate(for: $1) }
    }

    private var protectedItems: [PurchaseRightItem] {
        activeItems
            .filter { $0.hasAnyProtection && !isNeedingAttention($0) }
            .sorted { nearestRelevantDate(for: $0) < nearestRelevantDate(for: $1) }
    }

    private var receiptOnlyItems: [PurchaseRightItem] {
        activeItems
            .filter { !$0.hasAnyProtection }
            .sorted { $0.purchaseDate > $1.purchaseDate }
    }

    private var trackedValue: Decimal {
        activeItems.reduce(into: Decimal.zero) { total, item in
            total += item.price
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nextReturn: PurchaseRightItem? {
        activeItems
            .filter { $0.hasReturnWindow && $0.returnDeadline >= .now.startOfDay }
            .sorted { $0.returnDeadline < $1.returnDeadline }
            .first
    }

    private var nextWarranty: PurchaseRightItem? {
        activeItems
            .filter { $0.hasWarrantyCoverage && $0.warrantyEndDate >= .now.startOfDay }
            .sorted { $0.warrantyEndDate < $1.warrantyEndDate }
            .first
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isSearching {
                        PurchaseSearchSummaryPanel(
                            resultCount: filteredItems.count,
                            searchText: searchText
                        )
                    } else {
                        warrantySummaryPanel
                    }
                }
                .payGuardListSectionStyle()

                if isSearching {
                    Section("Tracked items") {
                        if filteredItems.isEmpty {
                            Text("No tracked items match this view yet. Add a product to track return and warranty dates.")
                                .font(PayGuardTheme.captionFont)
                                .foregroundStyle(PayGuardTheme.textSecondary)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(filteredItems) { item in
                                purchaseNavigationRow(for: item)
                            }
                        }
                    }
                    .payGuardListSectionStyle()
                } else {
                    if activeItems.isEmpty {
                        Section("Tracked items") {
                            Text("No tracked items match this view yet. Add a product to track return and warranty dates.")
                                .font(PayGuardTheme.captionFont)
                                .foregroundStyle(PayGuardTheme.textSecondary)
                                .padding(.vertical, 10)
                        }
                        .payGuardListSectionStyle()
                    }

                    if !needsActionItems.isEmpty {
                        Section("Needs action") {
                            ForEach(needsActionItems) { item in
                                purchaseNavigationRow(for: item)
                            }
                        }
                        .payGuardListSectionStyle()
                    }

                    if !protectedItems.isEmpty {
                        Section("Protected") {
                            ForEach(protectedItems) { item in
                                purchaseNavigationRow(for: item)
                            }
                        }
                        .payGuardListSectionStyle()
                    }

                    if !receiptOnlyItems.isEmpty {
                        Section("Receipt only") {
                            ForEach(receiptOnlyItems) { item in
                                purchaseNavigationRow(for: item)
                            }
                        }
                        .payGuardListSectionStyle()
                    }
                }

            }
            .navigationTitle("Purchases")
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .background(PayGuardBackdrop())
            .searchable(text: $searchText)
            .payGuardNavigationChrome()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            presentPurchaseEditor()
                        } label: {
                            Label("Add item".pmLocalized, systemImage: "plus")
                        }

                        Button {
                            if premiumAccess.canUseDocumentScan() {
                                showingSmartImport = true
                            } else {
                                premiumGate = .scanLimit
                            }
                        } label: {
                            Label("Scan receipt".pmLocalized, systemImage: "text.viewfinder")
                        }
                    } label: {
                        ToolbarCircleIcon(systemName: "plus", emphasized: true)
                    }
                    .accessibilityLabel("Warranty actions")
                }
            }
            .sheet(item: $editorPresentation) { presentation in
                NavigationStack {
                    PurchaseRightEditorView(importDraft: presentation.importDraft)
                }
            }
            .sheet(isPresented: $showingSmartImport) {
                SmartImportSourceSheet(
                    title: "Import from receipt, screenshot, or PDF",
                    detail: "Bring in a store receipt or scanned invoice and PayGuard will build a tracked item draft on-device."
                ) { payload in
                    previewImportDraft = PurchaseImportDraft.make(from: payload)
                }
            }
            .sheet(item: $previewImportDraft) { draft in
                NavigationStack {
                    PurchaseImportReviewView(draft: draft) { chosenDraft in
                        queuedImportDraft = chosenDraft
                        previewImportDraft = nil
                    }
                }
            }
            .onChange(of: previewImportDraft?.id) { _, newValue in
                guard newValue == nil, let queuedImportDraft else { return }
                DispatchQueue.main.async {
                    editorPresentation = PurchaseEditorPresentation(importDraft: queuedImportDraft)
                    self.queuedImportDraft = nil
                }
            }
            .sheet(item: $premiumGate) { gate in
                PremiumUpgradeSheet(gate: gate)
            }
        }
    }

    @ViewBuilder
    private func purchaseNavigationRow(for item: PurchaseRightItem) -> some View {
        NavigationLink {
            PurchaseRightDetailView(item: item)
        } label: {
            PurchaseRow(item: item)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(PayGuardTheme.destructive)
        }
    }

    private func isNeedingAttention(_ item: PurchaseRightItem) -> Bool {
        let returnNeedsAttention = item.hasReturnWindow && daysUntil(item.returnDeadline) <= 7
        let warrantyNeedsAttention = item.hasWarrantyCoverage && daysUntil(item.warrantyEndDate) <= 30
        return returnNeedsAttention || warrantyNeedsAttention
    }

    private func daysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: .now.startOfDay, to: date.startOfDay).day ?? 999
    }

    private var warrantySummaryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WarrantySummaryTile(
                    title: "Tracked",
                    value: "\(activeItems.count)",
                    symbol: "shippingbox.fill"
                )

                WarrantySummaryTile(
                    title: "Spent",
                    value: trackedValue.currencyString(code: "EUR"),
                    symbol: "creditcard.fill"
                )
            }

            VStack(spacing: 10) {
                if let nextReturn {
                    NavigationLink {
                        PurchaseRightDetailView(item: nextReturn)
                    } label: {
                        WarrantyCompactDateRow(
                            title: "Next return",
                            itemTitle: nextReturn.title,
                            value: nextReturn.returnDeadline.shortRelativeDescription,
                            price: nextReturn.price.currencyString(code: nextReturn.currencyCode),
                            symbol: "arrow.uturn.backward.circle.fill",
                            tone: .warning
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let nextWarranty {
                    NavigationLink {
                        PurchaseRightDetailView(item: nextWarranty)
                    } label: {
                        WarrantyCompactDateRow(
                            title: "Next warranty",
                            itemTitle: nextWarranty.title,
                            value: nextWarranty.warrantyEndDate.shortRelativeDescription,
                            price: nextWarranty.price.currencyString(code: nextWarranty.currencyCode),
                            symbol: "checkmark.shield.fill",
                            tone: .accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(PayGuardPremiumCardBackground(cornerRadius: 26))
    }

    private func presentPurchaseEditor() {
        guard premiumAccess.canAddPurchase(activeCount: activeItems.count) else {
            premiumGate = .purchaseLimit
            return
        }
        editorPresentation = PurchaseEditorPresentation(importDraft: nil)
    }

    private func nearestRelevantDate(for item: PurchaseRightItem) -> Date {
        item.nextProtectionDate ?? .distantFuture
    }

    private func delete(_ item: PurchaseRightItem) {
        item.attachments.forEach(AttachmentService.shared.delete)
        modelContext.delete(item)
    }
}


private struct PurchaseSearchSummaryPanel: View {
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
                Text(PMLocalized("%d tracked items found", resultCount))
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

private struct WarrantySummaryTile: View {
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

private struct WarrantyCompactDateRow: View {
    let title: String
    let itemTitle: String
    let value: String
    let price: String
    let symbol: String
    let tone: PayGuardBadgeTone

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tone.color)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(tone.color.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title.localizedKey)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(PMLocalized("%@ · %@", itemTitle, value))
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(PayGuardTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Text(price.localizedKey)
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

private struct PurchaseRow: View {
    let item: PurchaseRightItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Text(item.price.currencyString(code: item.currencyCode))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
            }

            Text(item.seller)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(PayGuardTheme.textSecondary)

            HStack(spacing: 10) {
                if item.hasReturnWindow {
                    PremiumStatusBadge(
                        title: "Return",
                        value: item.returnDeadline.shortRelativeDescription,
                        tone: tone(for: item.returnDeadline, warningDays: 7),
                        systemName: "arrow.uturn.backward.circle.fill"
                    )
                }
                if item.hasWarrantyCoverage {
                    PremiumStatusBadge(
                        title: "Warranty",
                        value: item.warrantyEndDate.shortRelativeDescription,
                        tone: tone(for: item.warrantyEndDate, warningDays: 30),
                        systemName: "checkmark.shield.fill"
                    )
                }
                if !item.hasAnyProtection {
                    PremiumStatusBadge(
                        title: "Status",
                        value: "Receipt only",
                        tone: .positive,
                        systemName: "doc.text.fill"
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PayGuardTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
        .opacity(item.isArchived ? 0.58 : 1)
    }

    private func tone(for date: Date, warningDays: Int) -> PayGuardBadgeTone {
        let remainingDays = Calendar.current.dateComponents([.day], from: .now.startOfDay, to: date.startOfDay).day ?? 0
        if remainingDays < 0 {
            return .critical
        }
        if remainingDays <= warningDays {
            return .warning
        }
        return .positive
    }
}

struct PurchaseRightEditorView: View {
    @Environment(PremiumAccessController.self) private var premiumAccess
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PurchaseRightItem.updatedAt, order: .reverse) private var allItems: [PurchaseRightItem]
    @Query(sort: \FamilyMember.name) private var members: [FamilyMember]
    @StateObject private var notificationState = NotificationPermissionState()

    let existingItem: PurchaseRightItem?
    let importDraft: PurchaseImportDraft?

    @State private var title = ""
    @State private var seller = ""
    @State private var purchaseDate = Date.now
    @State private var hasReturnWindow = true
    @State private var hasWarrantyCoverage = true
    @State private var returnDays = 14
    @State private var warrantyMonths = 24
    @State private var priceText = ""
    @State private var currencyCode = "EUR"
    @State private var category = PurchaseCategory.general
    @State private var ownerName = "You"
    @State private var payerName = "You"
    @State private var notes = ""
    @State private var selectedChecklistTasks: Set<String> = []
    @State private var returnRemindersEnabled = false
    @State private var warrantyRemindersEnabled = false
    @State private var selectedReturnOffsets: Set<Int> = [7, 3, 1]
    @State private var selectedWarrantyOffsets: Set<Int> = [30, 7]
    @State private var returnReminderTime = Date.reminderClock(hour: 9, minute: 0)
    @State private var warrantyReminderTime = Date.reminderClock(hour: 9, minute: 0)
    @State private var validationMessage: String?
    @State private var premiumGate: PremiumGate?
    @State private var pendingAttachments: [AttachmentRecord] = []
    @State private var didSave = false

    init(existingItem: PurchaseRightItem? = nil, importDraft: PurchaseImportDraft? = nil) {
        self.existingItem = existingItem
        self.importDraft = importDraft
    }

    var body: some View {
        ZStack {
            PayGuardBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(existingItem == nil ? "New item" : "Edit item")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                        Text("Capture the item, its return window, and its warranty in one polished record.")
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    PurchasePremiumCard(title: "Essentials", symbol: "shippingbox.fill") {
                        PurchasePremiumTextField(title: "Product name", placeholder: "AirPods Pro, Office Chair", text: $title)
                        PurchasePremiumFieldDivider()
                        PurchasePremiumTextField(title: "Store or seller", placeholder: "Apple Store, IKEA, Amazon", text: $seller)
                        PurchasePremiumFieldDivider()
                        DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                        PurchasePremiumFieldDivider()
                        Toggle("Track return period", isOn: $hasReturnWindow)
                            .tint(PayGuardTheme.accent)
                        if hasReturnWindow {
                            PurchasePremiumFieldDivider()
                            Stepper(PMLocalized("Return period: %d days", returnDays), value: $returnDays, in: 1...60)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(PayGuardTheme.textPrimary)
                        }
                        PurchasePremiumFieldDivider()
                        Toggle("Track warranty period", isOn: $hasWarrantyCoverage)
                            .tint(PayGuardTheme.accent)
                        if hasWarrantyCoverage {
                            PurchasePremiumFieldDivider()
                            Stepper(PMLocalized("Warranty period: %d months", warrantyMonths), value: $warrantyMonths, in: 1...60)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(PayGuardTheme.textPrimary)
                        }
                        PurchasePremiumFieldDivider()
                        HStack(spacing: 12) {
                            PurchasePremiumTextField(title: "Price", placeholder: "299.99", text: $priceText)
                                .keyboardType(.decimalPad)
                            PurchasePremiumPickerField(title: "Currency") {
                                Picker("Currency", selection: $currencyCode) {
                                    ForEach(supportedCurrencies, id: \.self) { code in
                                        Text(code).tag(code)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        PurchasePremiumFieldDivider()
                        PurchasePremiumPickerField(title: "Category") {
                            Picker("Category", selection: $category) {
                                ForEach(PurchaseCategory.allCases) { item in
                                    Text(item.label).tag(item)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    if premiumAccess.canUseFamilyManagement() {
                        PurchasePremiumCard(title: "Ownership", symbol: "person.2.crop.square.stack.fill") {
                            PurchasePremiumPickerField(title: "Owner") {
                                Picker("Owner", selection: $ownerName) {
                                    ForEach(memberNames, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            PurchasePremiumFieldDivider()
                            PurchasePremiumPickerField(title: "Payer") {
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

                    PurchasePremiumCard(title: "Action list", symbol: "checklist.checked") {
                        Text("Add only the follow-up tasks you want for this purchase.")
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)

                        ForEach(checklistTemplates, id: \.title) { task in
                            Toggle(task.title, isOn: Binding(
                                get: { selectedChecklistTasks.contains(task.title) },
                                set: { isOn in
                                    if isOn {
                                        selectedChecklistTasks.insert(task.title)
                                    } else {
                                        selectedChecklistTasks.remove(task.title)
                                    }
                                }
                            ))
                            .tint(PayGuardTheme.accent)
                        }
                    }

                    PurchasePremiumCard(title: "Alerts", symbol: "bell.badge.fill") {
                        if hasReturnWindow {
                            Toggle("Return reminders", isOn: $returnRemindersEnabled)
                                .tint(PayGuardTheme.accent)
                            if returnRemindersEnabled {
                                if !premiumAccess.supportsMultipleReminders() {
                                    PurchasePremiumFieldDivider()
                                    reminderUnlockNotice
                                }
                                PurchasePremiumFieldDivider()
                                reminderSelectionRow(
                                    title: "Return timings",
                                    choices: returnReminderChoices,
                                    selection: $selectedReturnOffsets
                                )
                                PurchasePremiumFieldDivider()
                                reminderTimeRow(
                                    title: "Return reminder time",
                                    detail: "Every return alert lands at this hour.",
                                    selection: $returnReminderTime
                                )
                            }
                        } else {
                            Text("Return tracking is off for this item.")
                                .font(PayGuardTheme.captionFont)
                                .foregroundStyle(PayGuardTheme.textSecondary)
                        }

                        PurchasePremiumFieldDivider()
                        if hasWarrantyCoverage {
                            Toggle("Warranty reminders", isOn: $warrantyRemindersEnabled)
                                .tint(PayGuardTheme.accent)
                            if warrantyRemindersEnabled {
                                if !premiumAccess.supportsMultipleReminders() {
                                    PurchasePremiumFieldDivider()
                                    reminderUnlockNotice
                                }
                                PurchasePremiumFieldDivider()
                                reminderSelectionRow(
                                    title: "Warranty timings",
                                    choices: warrantyReminderChoices,
                                    selection: $selectedWarrantyOffsets
                                )
                                PurchasePremiumFieldDivider()
                                reminderTimeRow(
                                    title: "Warranty reminder time",
                                    detail: "Every warranty alert lands at this hour.",
                                    selection: $warrantyReminderTime
                                )
                            }
                        } else {
                            Text("Warranty tracking is off for this item.")
                                .font(PayGuardTheme.captionFont)
                                .foregroundStyle(PayGuardTheme.textSecondary)
                        }

                        if ((hasReturnWindow && returnRemindersEnabled) || (hasWarrantyCoverage && warrantyRemindersEnabled)) &&
                            notificationState.status != .authorized &&
                            notificationState.status != .provisional &&
                            notificationState.status != .ephemeral {
                            PurchasePremiumFieldDivider()
                            Button(notificationCTA) {
                                handleNotificationCTA()
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                        }
                    }

                    PurchasePremiumCard(title: "Notes", symbol: "note.text") {
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

                    if existingItem == nil {
                        PurchasePremiumCard(title: "Attachments", symbol: "paperclip") {
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
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(existingItem == nil ? "New item" : "Edit item")
        .navigationBarTitleDisplayMode(.inline)
        .payGuardNavigationChrome()
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
            await notificationState.refresh()
            resetForm()
            if let existingItem {
                title = existingItem.title
                seller = existingItem.seller
                purchaseDate = existingItem.purchaseDate
                hasReturnWindow = existingItem.hasReturnWindow
                hasWarrantyCoverage = existingItem.hasWarrantyCoverage
                returnDays = max(1, Calendar.current.dateComponents([.day], from: existingItem.purchaseDate, to: existingItem.returnDeadline).day ?? 14)
                warrantyMonths = max(1, Calendar.current.dateComponents([.month], from: existingItem.purchaseDate, to: existingItem.warrantyEndDate).month ?? 24)
                priceText = "\(existingItem.price)"
                currencyCode = existingItem.currencyCode
                category = existingItem.category
                ownerName = existingItem.ownerName
                payerName = existingItem.payerName
                notes = existingItem.notes
                selectedChecklistTasks = Set(existingItem.checklist.map(\.title))
                selectedReturnOffsets = Set(existingItem.returnReminderOffsets)
                selectedWarrantyOffsets = Set(existingItem.warrantyReminderOffsets)
                returnRemindersEnabled = existingItem.hasReturnWindow && !existingItem.returnReminderOffsets.isEmpty
                warrantyRemindersEnabled = existingItem.hasWarrantyCoverage && !existingItem.warrantyReminderOffsets.isEmpty
                returnReminderTime = Date.reminderClock(
                    hour: existingItem.returnReminderHour,
                    minute: existingItem.returnReminderMinute
                )
                warrantyReminderTime = Date.reminderClock(
                    hour: existingItem.warrantyReminderHour,
                    minute: existingItem.warrantyReminderMinute
                )
                applyFreePlanConstraints()
                return
            }

            if let importDraft {
                title = importDraft.title
                seller = importDraft.seller
                purchaseDate = importDraft.purchaseDate
                priceText = importDraft.priceText
                currencyCode = importDraft.currencyCode
                category = importDraft.category
                notes = importDraft.notes
                pendingAttachments = importDraft.attachments
                applyFreePlanConstraints()
            }
        }
        .alert("Purchase Incomplete", isPresented: Binding(
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
        .onChange(of: hasReturnWindow) { _, isOn in
            if !isOn {
                returnRemindersEnabled = false
            }
        }
        .onChange(of: hasWarrantyCoverage) { _, isOn in
            if !isOn {
                warrantyRemindersEnabled = false
            }
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

    private var checklistTemplates: [(title: String, sortOrder: Int)] {
        [
            (PMLocalized("Contact seller if needed"), 0),
            (PMLocalized("Prepare return label or claim photos"), 1),
            (PMLocalized("Check warranty terms"), 2)
        ]
    }

    private var returnReminderChoices: [Int] {
        [7, 3, 1, 0]
    }

    private var warrantyReminderChoices: [Int] {
        [30, 14, 7, 1]
    }

    private var notificationCTA: String {
        notificationState.status == .denied ? PMLocalized("Open notification settings") : PMLocalized("Allow notifications")
    }

    private var formSeed: String {
        if let existingItem {
            return "existing-\(existingItem.id.uuidString)"
        }
        if let importDraft {
            return "import-\(importDraft.id.uuidString)"
        }
        return "new-purchase"
    }

    private func resetForm() {
        title = ""
        seller = ""
        purchaseDate = .now
        hasReturnWindow = true
        hasWarrantyCoverage = true
        returnDays = 14
        warrantyMonths = 24
        priceText = ""
        currencyCode = "EUR"
        category = .general
        ownerName = memberNames.first ?? "You"
        payerName = memberNames.first ?? "You"
        notes = ""
        pendingAttachments = []
        didSave = false
        selectedChecklistTasks = []
        returnRemindersEnabled = false
        warrantyRemindersEnabled = false
        selectedReturnOffsets = [7, 3, 1]
        selectedWarrantyOffsets = [30, 7]
        returnReminderTime = .reminderClock(hour: 9, minute: 0)
        warrantyReminderTime = .reminderClock(hour: 9, minute: 0)
        validationMessage = nil
    }

    private func save() {
        let activeItemCount = allItems.filter { !$0.isArchived }.count
        if existingItem == nil && !premiumAccess.canAddPurchase(activeCount: activeItemCount) {
            validationMessage = PMLocalized("Free includes up to %d active protected purchases. Unlock Pro to add more.", PremiumAccessController.freePurchaseLimit)
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = PMLocalized("Please enter a product name.")
            return
        }
        guard !seller.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = PMLocalized("Please enter the store or seller.")
            return
        }
        guard let price = Decimal(string: priceText.replacingOccurrences(of: ",", with: ".")) else {
            validationMessage = PMLocalized("Please enter a valid price.")
            return
        }

        let returnDeadline = Calendar.current.date(byAdding: .day, value: returnDays, to: purchaseDate) ?? purchaseDate
        let warrantyEndDate = Calendar.current.date(byAdding: .month, value: warrantyMonths, to: purchaseDate) ?? purchaseDate
        let returnReminderOffsets = hasReturnWindow && returnRemindersEnabled ? selectedReturnOffsets.sorted(by: >) : []
        let warrantyReminderOffsets = hasWarrantyCoverage && warrantyRemindersEnabled ? selectedWarrantyOffsets.sorted(by: >) : []
        let returnReminderHour = returnReminderTime.hourComponent
        let returnReminderMinute = returnReminderTime.minuteComponent
        let warrantyReminderHour = warrantyReminderTime.hourComponent
        let warrantyReminderMinute = warrantyReminderTime.minuteComponent
        let ownerMemberID = premiumAccess.canUseFamilyManagement() ? memberID(for: ownerName) : nil
        let payerMemberID = premiumAccess.canUseFamilyManagement() ? memberID(for: payerName) : nil
        let resolvedOwnerName = premiumAccess.canUseFamilyManagement() ? ownerName : "You"
        let resolvedPayerName = premiumAccess.canUseFamilyManagement() ? payerName : "You"
        let checklist = buildChecklist(from: existingItem?.checklist ?? [])

        if let existingItem {
            let removedTasks = existingItem.checklist.filter { !selectedChecklistTasks.contains($0.title) }
            removedTasks.forEach(modelContext.delete)
            existingItem.title = title
            existingItem.seller = seller
            existingItem.purchaseDate = purchaseDate
            existingItem.hasReturnWindow = hasReturnWindow
            existingItem.hasWarrantyCoverage = hasWarrantyCoverage
            existingItem.returnDeadline = returnDeadline
            existingItem.warrantyEndDate = warrantyEndDate
            existingItem.price = price
            existingItem.currencyCode = currencyCode.uppercased()
            existingItem.category = category
            existingItem.ownerMemberID = ownerMemberID
            existingItem.payerMemberID = payerMemberID
            existingItem.ownerName = resolvedOwnerName
            existingItem.payerName = resolvedPayerName
            existingItem.notes = notes
            existingItem.returnReminderOffsets = returnReminderOffsets
            existingItem.warrantyReminderOffsets = warrantyReminderOffsets
            existingItem.returnReminderHour = returnReminderHour
            existingItem.returnReminderMinute = returnReminderMinute
            existingItem.warrantyReminderHour = warrantyReminderHour
            existingItem.warrantyReminderMinute = warrantyReminderMinute
            existingItem.checklist = checklist
            existingItem.updatedAt = .now
            NotificationScheduler.shared.replaceNotifications(for: existingItem)
        } else {
            let item = PurchaseRightItem(
                title: title,
                seller: seller,
                purchaseDate: purchaseDate,
                hasReturnWindow: hasReturnWindow,
                hasWarrantyCoverage: hasWarrantyCoverage,
                returnDeadline: returnDeadline,
                warrantyEndDate: warrantyEndDate,
                price: price,
                currencyCode: currencyCode.uppercased(),
                category: category,
                ownerMemberID: ownerMemberID,
                payerMemberID: payerMemberID,
                ownerName: resolvedOwnerName,
                payerName: resolvedPayerName,
                notes: notes,
                returnReminderOffsets: returnReminderOffsets,
                warrantyReminderOffsets: warrantyReminderOffsets,
                returnReminderHour: returnReminderHour,
                returnReminderMinute: returnReminderMinute,
                warrantyReminderHour: warrantyReminderHour,
                warrantyReminderMinute: warrantyReminderMinute,
                attachments: pendingAttachments,
                checklist: checklist
            )
            modelContext.insert(item)
            NotificationScheduler.shared.replaceNotifications(for: item)
        }

        didSave = true
        dismiss()
    }

    private func cleanupUnattachedFilesIfNeeded() {
        guard existingItem == nil, !didSave else { return }
        pendingAttachments.forEach(AttachmentService.shared.delete)
        pendingAttachments.removeAll()
    }

    private func buildChecklist(from existingTasks: [PurchaseChecklistTask]) -> [PurchaseChecklistTask] {
        checklistTemplates.compactMap { template in
            guard selectedChecklistTasks.contains(template.title) else { return nil }
            if let existingTask = existingTasks.first(where: { $0.title == template.title }) {
                existingTask.sortOrder = template.sortOrder
                return existingTask
            }
            return PurchaseChecklistTask(title: template.title, sortOrder: template.sortOrder)
        }
    }

    @ViewBuilder
    private func reminderSelectionRow(title: String, choices: [Int], selection: Binding<Set<Int>>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.localizedKey)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        if premiumAccess.supportsMultipleReminders() {
                            if selection.wrappedValue.contains(choice) {
                                selection.wrappedValue.remove(choice)
                            } else {
                                selection.wrappedValue.insert(choice)
                            }
                        } else {
                            if selection.wrappedValue.contains(choice) {
                                selection.wrappedValue.remove(choice)
                            } else {
                                selection.wrappedValue = [choice]
                            }
                        }
                    } label: {
                        PurchaseReminderChip(
                            title: reminderLabel(for: choice),
                            isSelected: selection.wrappedValue.contains(choice)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var reminderUnlockNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Free plan reminder limit")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(PayGuardTheme.textPrimary)
            Text("Choose one reminder timing per alert, or unlock Pro to combine multiple alerts.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(PayGuardTheme.textSecondary)
            Button("Unlock multiple reminders") {
                premiumGate = .multipleReminders
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
    }

    private func reminderTimeRow(title: String, detail: String, selection: Binding<Date>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.localizedKey)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                Text(detail.localizedKey)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            Spacer()
            DatePicker(title.localizedKey, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
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

    private func applyFreePlanConstraints() {
        guard !premiumAccess.supportsMultipleReminders() else { return }
        selectedReturnOffsets = premiumAccess.clampedOffsets(from: selectedReturnOffsets)
        selectedWarrantyOffsets = premiumAccess.clampedOffsets(from: selectedWarrantyOffsets)
    }
}

private struct PurchasePremiumCard<Content: View>: View {
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

private struct PurchaseEditorPresentation: Identifiable {
    let id = UUID()
    let importDraft: PurchaseImportDraft?
}

struct PurchaseImportDraft: Identifiable {
    let id = UUID()
    let title: String
    let seller: String
    let purchaseDate: Date
    let priceText: String
    let currencyCode: String
    let category: PurchaseCategory
    let notes: String
    let recognizedTextPreview: String
    let attachments: [AttachmentRecord]

    static func make(from payload: SmartImportPayload) -> PurchaseImportDraft {
        PurchaseImportDraft(
            title: inferredPurchaseTitle(in: payload.text),
            seller: inferredPurchaseSeller(in: payload.text),
            purchaseDate: detectedRelevantDate(in: payload.text, preferFuture: false) ?? .now,
            priceText: bestReceiptAmount(in: payload.text) ?? "",
            currencyCode: detectedCurrency(in: payload.text) ?? "EUR",
            category: inferredPurchaseCategory(in: payload.text),
            notes: PMLocalized("Imported from %@ with on-device text recognition.", payload.sourceName),
            recognizedTextPreview: payload.text,
            attachments: payload.attachment.map { [$0] } ?? []
        )
    }
}

private struct PurchaseImportReviewView: View {
    let draft: PurchaseImportDraft
    let onUse: (PurchaseImportDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var didUseDraft = false

    var body: some View {
        List {
            Section {
                Text("PayGuard found the most likely product, seller, date, and amount fields. Continue to the editor to fine-tune the deadlines and coverage.")
                    .font(PayGuardTheme.captionFont)
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }
            .payGuardListSectionStyle()

            Section("Suggested fields") {
                reviewRow("Title", draft.title)
                reviewRow("Seller", draft.seller)
                reviewRow("Purchase date", PayGuardFormatters.mediumDate.string(from: draft.purchaseDate))
                reviewRow("Price", draft.priceText.isEmpty ? PMLocalized("Not detected") : PMLocalized("%@ %@", draft.priceText, draft.currencyCode))
                reviewRow("Category", draft.category.rawValue.capitalized)
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
}

private func inferredPurchaseSeller(in text: String) -> String {
    let lines = text
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if let labeledName = labeledImportedEntityName(in: lines) {
        return labeledName
    }

    if let organizationLine = lines.first(where: looksLikeImportedOrganizationLine(_:)),
       let organizationName = cleanedImportedEntityName(from: organizationLine) {
        return organizationName
    }

    return lines.first(where: { line in
        let lower = line.lowercased()
        let normalized = lower.folding(options: [.diacriticInsensitive], locale: .current)
        let blockedFragments = [
            "invoice",
            "receipt",
            "dekont",
            "iban",
            "swift",
            "total",
            "bilgileri",
            "bilgisi",
            "alici",
            "duzenleyen",
            "urun aciklamasi",
            "sira",
            "belge numarasi",
            "duzenleme tarihi"
        ]
        return line.count <= 40 &&
            line.rangeOfCharacter(from: .letters) != nil &&
            !looksLikeGenericImportedHeading(line) &&
            !blockedFragments.contains(where: normalized.contains)
    }) ?? PMLocalized("Imported seller")
}

private func inferredPurchaseTitle(in text: String) -> String {
    let lines = text
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if let labeledTitle = labeledImportedServiceTitle(in: lines) {
        return labeledTitle
    }

    if let serviceLine = lines.first(where: looksLikeImportedServiceTitleLine(_:)),
       let serviceName = cleanedImportedServiceTitle(from: serviceLine) {
        return serviceName
    }

    if let feeLine = lines.first(where: looksLikeImportedPurchaseTitleLine(_:)),
       let cleanedTitle = cleanedImportedPurchaseTitle(from: feeLine) {
        return cleanedTitle
    }

    return lines.first(where: { line in
        let lower = line.lowercased()
        let normalized = lower.folding(options: [.diacriticInsensitive], locale: .current)
        let blockedFragments = [
            "total",
            "vat",
            "receipt",
            "invoice",
            "tuition invoice",
            "id household",
            "account balance",
            "payment plan",
            "academic year",
            "description amount",
            "charges/credits",
            "payment received",
            "one-pay",
            "iban",
            "swift",
            "bilgileri",
            "bilgisi",
            "duzenleyen",
            "urun aciklamasi",
            "urun açıklaması",
            "sira",
            "no",
            "belge numarasi",
            "duzenleme tarihi",
            "duzenleme saati"
        ]
        return line.count <= 42 &&
            line.rangeOfCharacter(from: .letters) != nil &&
            !looksLikeGenericImportedHeading(line) &&
            !blockedFragments.contains(where: normalized.contains)
    }) ?? lines.first ?? PMLocalized("Imported item")
}

private func inferredPurchaseCategory(in text: String) -> PurchaseCategory {
    let lower = text.lowercased()
    if lower.contains("tuition") ||
        lower.contains("academic year") ||
        lower.contains("school") ||
        lower.contains("grade ") ||
        lower.contains("student") ||
        lower.contains("academy") ||
        lower.contains("university") ||
        lower.contains("college") {
        return .general
    }
    if lower.contains("apple") || lower.contains("airpods") || lower.contains("iphone") || lower.contains("laptop") {
        return .electronics
    }
    if lower.contains("ikea") || lower.contains("chair") || lower.contains("table") || lower.contains("home") {
        return .home
    }
    if lower.contains("bag") || lower.contains("shoe") || lower.contains("fashion") {
        return .fashion
    }
    if lower.contains("flight") || lower.contains("hotel") || lower.contains("travel") {
        return .travel
    }
    if lower.contains("playstation") || lower.contains("xbox") || lower.contains("nintendo") {
        return .gaming
    }
    if lower.contains("washer") || lower.contains("fridge") || lower.contains("appliance") {
        return .appliances
    }
    return .general
}

private func bestReceiptAmount(in text: String) -> String? {
    let lines = text.components(separatedBy: .newlines)
    for line in lines.reversed() {
        let lower = line.lowercased()
        if lower.contains("total"), let amount = bestAmountString(in: line) {
            return amount
        }
    }
    return bestAmountString(in: text)
}

private func labeledImportedEntityName(in lines: [String]) -> String? {
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
                  let cleaned = cleanedImportedEntityName(from: String(line[range])) else {
                continue
            }
            return cleaned
        }
    }

    let labelOnlyPattern = #"(?i)^(merchant|seller|company|institution|provider|recipient|beneficiary|issuer|doctor|hekim|duzenleyen|düzenleyen|alici|alıcı|unvan|kurum|firma|işyeri|isyeri)$"#
    for (index, line) in lines.enumerated() where index + 1 < lines.count {
        guard line.range(of: labelOnlyPattern, options: .regularExpression) != nil,
              let cleaned = cleanedImportedEntityName(from: lines[index + 1]) else {
            continue
        }
        return cleaned
    }

    return nil
}

private func looksLikeImportedOrganizationLine(_ line: String) -> Bool {
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

private func cleanedImportedEntityName(from line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawName = trimmed
        .components(separatedBy: ",")
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let rawName else { return nil }

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

private func looksLikeImportedPurchaseTitleLine(_ line: String) -> Bool {
    let lower = line.lowercased()
    return lower.contains("tuition fee") ||
        lower.contains("membership fee") ||
        lower.contains("course fee") ||
        lower.contains("school fee") ||
        lower.contains("warranty") ||
        lower.contains("model") ||
        lower.contains("product")
}

private func cleanedImportedPurchaseTitle(from line: String) -> String? {
    var candidate = line
        .replacingOccurrences(of: #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"[€$£₺]\s*\d[\d.,]*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\bsubtotal\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if let range = candidate.range(of: #"\b(?:Mr\.|Mrs\.|Ms\.|Herr|Frau)\b.*"#, options: .regularExpression) {
        candidate.removeSubrange(range)
    }

    candidate = candidate
        .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard candidate.rangeOfCharacter(from: .letters) != nil else {
        return nil
    }

    guard !looksLikeGenericImportedHeading(candidate) else {
        return nil
    }

    return candidate
}

private struct PurchasePremiumTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.pmLocalized.uppercased())
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(PayGuardTheme.textSecondary)
            TextField(placeholder.localizedKey, text: $text)
                .payGuardTextInputStyle()
        }
    }
}

private struct PurchasePremiumPickerField<PickerContent: View>: View {
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

private struct PurchasePremiumFieldDivider: View {
    var body: some View {
        Divider()
            .overlay(PayGuardTheme.divider)
    }
}

private struct PurchaseReminderChip: View {
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

struct PurchaseRightDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let item: PurchaseRightItem

    @State private var showingEdit = false
    @State private var copiedDraftLabel: String?

    private var checklistDoneCount: Int {
        item.checklist.filter(\.isDone).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PurchaseDetailHeroCard(item: item, protectionLabel: lifecycleProtectionLabel)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    PremiumDetailMetricCard(
                        title: "Value",
                        value: item.price.currencyString(code: item.currencyCode),
                        symbol: "creditcard.fill"
                    )
                    if item.hasReturnWindow {
                        PremiumDetailMetricCard(
                            title: "Return deadline",
                            value: item.returnDeadline.shortRelativeDescription,
                            symbol: "arrow.uturn.backward.circle.fill"
                        )
                    }
                    if item.hasWarrantyCoverage {
                        PremiumDetailMetricCard(
                            title: "Warranty end",
                            value: item.warrantyEndDate.shortRelativeDescription,
                            symbol: "checkmark.shield.fill"
                        )
                    }
                    PremiumDetailMetricCard(
                        title: "Checklist",
                        value: PMLocalized("%d/%d done", checklistDoneCount, item.checklist.count),
                        symbol: "checklist"
                    )
                }

                PremiumDetailPanel(title: "Details", symbol: "list.bullet.rectangle.portrait.fill") {
                    PremiumDetailKeyValueRow(title: "Seller", value: item.seller)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Category", value: item.category.label)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Purchase date", value: PayGuardFormatters.mediumDate.string(from: item.purchaseDate))
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Owner", value: item.ownerName)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Payer", value: item.payerName)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(
                        title: "Return reminders",
                        value: item.hasReturnWindow ? (item.returnReminderOffsets.isEmpty ? PMLocalized("Off") : item.returnReminderOffsets.reminderSummary) : PMLocalized("Not tracked")
                    )
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(
                        title: "Warranty reminders",
                        value: item.hasWarrantyCoverage ? (item.warrantyReminderOffsets.isEmpty ? PMLocalized("Off") : item.warrantyReminderOffsets.reminderSummary) : PMLocalized("Not tracked")
                    )
                    if item.hasReturnWindow && !item.returnReminderOffsets.isEmpty {
                        PremiumDetailDivider()
                        PremiumDetailKeyValueRow(
                            title: "Return reminder time",
                            value: Date.reminderClock(
                                hour: item.returnReminderHour,
                                minute: item.returnReminderMinute
                            ).shortTimeString
                        )
                    }
                    if item.hasWarrantyCoverage && !item.warrantyReminderOffsets.isEmpty {
                        PremiumDetailDivider()
                        PremiumDetailKeyValueRow(
                            title: "Warranty reminder time",
                            value: Date.reminderClock(
                                hour: item.warrantyReminderHour,
                                minute: item.warrantyReminderMinute
                            ).shortTimeString
                        )
                    }
                    if !item.notes.isEmpty {
                        PremiumDetailDivider()
                        PremiumNoteBlock(text: item.notes)
                    }
                }

                PremiumDetailPanel(title: "Claim assistant", symbol: "doc.text.magnifyingglass") {
                    VStack(spacing: 12) {
                        if item.hasReturnWindow && item.returnDeadline >= .now.startOfDay {
                            claimDraftCard(
                                title: "Return request draft",
                                detail: "Use this when you want to ask for a refund or start a return before the window closes.",
                                draft: returnDraft,
                                copyLabel: "Copy return draft"
                            )
                        }

                        if item.hasWarrantyCoverage && item.warrantyEndDate >= .now.startOfDay {
                            claimDraftCard(
                                title: "Warranty claim draft",
                                detail: "Use this when you need to contact the seller or brand about a coverage issue.",
                                draft: warrantyDraft,
                                copyLabel: "Copy warranty draft"
                            )
                        }
                    }
                }

                PremiumDetailPanel(title: "Lifecycle", symbol: "clock.arrow.circlepath") {
                    PremiumDetailKeyValueRow(title: "Recorded", value: PayGuardFormatters.mediumDate.string(from: item.createdAt))
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Last updated", value: PayGuardFormatters.mediumDate.string(from: item.updatedAt))
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Protection state", value: lifecycleProtectionLabel)
                    PremiumDetailDivider()
                    PremiumDetailKeyValueRow(title: "Attachment vault", value: PMLocalized("%d file(s)", item.attachments.count))
                }

                PremiumDetailPanel(title: "Action checklist", symbol: "checklist.checked") {
                    if item.checklist.isEmpty {
                        Text("No action list selected for this purchase.".localizedKey)
                            .font(PayGuardTheme.captionFont)
                            .foregroundStyle(PayGuardTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(item.checklist.sorted(by: { $0.sortOrder < $1.sortOrder })) { task in
                                PremiumChecklistRow(task: task)
                            }
                        }
                    }
                }

                PremiumDetailPanel(title: "Attachment vault", symbol: "doc.richtext.fill") {
                    AttachmentGalleryView(
                        attachments: item.attachments,
                        onImported: { attachment in
                            item.attachments.append(attachment)
                            item.updatedAt = .now
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
        .navigationTitle(item.title)
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
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                PurchaseRightEditorView(existingItem: item)
            }
        }
        .alert("Draft copied", isPresented: Binding(
            get: { copiedDraftLabel != nil },
            set: { if !$0 { copiedDraftLabel = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text((copiedDraftLabel ?? "").pmLocalized)
        }
    }

    private var returnDraft: String {
        PMLocalized(
            "Hello,\n\nI would like to start a return for %@, purchased from %@ on %@.\n\nThe return window is open until %@. Please let me know the next steps, return label instructions, and any reference number I should include.\n\nThank you.",
            item.title,
            item.seller,
            PayGuardFormatters.mediumDate.string(from: item.purchaseDate),
            PayGuardFormatters.mediumDate.string(from: item.returnDeadline)
        )
    }

    private var warrantyDraft: String {
        PMLocalized(
            "Hello,\n\nI need help with a warranty claim for %@, purchased from %@ on %@.\n\nThe warranty coverage is active until %@. Please let me know what documents, photos, or claim steps you need from me.\n\nThank you.",
            item.title,
            item.seller,
            PayGuardFormatters.mediumDate.string(from: item.purchaseDate),
            PayGuardFormatters.mediumDate.string(from: item.warrantyEndDate)
        )
    }

    private var lifecycleProtectionLabel: String {
        if item.hasReturnWindow && item.returnDeadline >= .now.startOfDay {
            return PMLocalized("Return window still open")
        }
        if item.hasWarrantyCoverage && item.warrantyEndDate >= .now.startOfDay {
            return PMLocalized("Warranty still active")
        }
        if !item.hasAnyProtection {
            return PMLocalized("Manual record only")
        }
        return PMLocalized("Protection period ended")
    }

    private func claimDraftCard(title: String, detail: String, draft: String, copyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PayGuardTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(PayGuardTheme.accent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title.localizedKey)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    Text(detail.localizedKey)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
            }

            Text(draft)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(PayGuardTheme.textPrimary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PayGuardTheme.inputFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PayGuardTheme.stroke, lineWidth: 1)
                }

            Button(copyLabel.localizedKey) {
                UIPasteboard.general.string = draft
                copiedDraftLabel = copyLabel
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PayGuardTheme.surface.opacity(0.74))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}

private struct PurchaseDetailHeroCard: View {
    let item: PurchaseRightItem
    let protectionLabel: String

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
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(PayGuardTheme.accent)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(PayGuardTheme.textPrimary)
                                .lineLimit(2)
                            Text(item.seller)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(PayGuardTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(protectionLabel.localizedKey)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule(style: .continuous).fill(PayGuardTheme.accent.opacity(0.12)))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(item.price.currencyString(code: item.currencyCode))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textPrimary)
                        Text(item.category.label)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(PayGuardTheme.textSecondary)
                    }

                    Text(PMLocalized("Purchased on %@", PayGuardFormatters.mediumDate.string(from: item.purchaseDate)))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
            }
        }
        .padding(20)
        .background(PayGuardPremiumCardBackground(cornerRadius: 30))
    }
}

private struct PremiumChecklistRow: View {
    @Bindable var task: PurchaseChecklistTask

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                task.isDone.toggle()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(task.isDone ? PayGuardTheme.accent : PayGuardTheme.textSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title.localizedKey)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
                    .strikethrough(task.isDone)
                if !task.note.isEmpty {
                    Text(task.note.localizedKey)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(PayGuardTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(PayGuardTheme.inputFill.opacity(0.92))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }
}
