//
//  FamilyView.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import SwiftData
import SwiftUI

struct FamilyView: View {
    @Environment(PremiumAccessController.self) private var premiumAccess
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.createdAt) private var members: [FamilyMember]
    @Query private var subscriptions: [SubscriptionRecord]
    @Query private var purchases: [PurchaseRightItem]

    @State private var newMemberName = ""
    @State private var role: MemberRole = .adult
    @State private var duplicateNameMessage: String?
    @State private var premiumGate: PremiumGate?

    private var memberTotals: [MemberTotal] {
        BillingEngine.shared.snapshot(subscriptions: subscriptions, purchases: purchases, members: members).memberTotals
    }

    private var householdSnapshot: DashboardSnapshot {
        BillingEngine.shared.snapshot(subscriptions: subscriptions, purchases: purchases, members: members)
    }

    var body: some View {
        Group {
            if premiumAccess.canUseFamilyManagement() {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionTitleView(
                            eyebrow: "Household",
                            title: "Keep shared owners and payers organized without cluttering the main nav.",
                            detail: "Assignments stay local today, and this structure is ready for future sync or sharing layers later."
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        overviewStrip

                        PayGuardPanel(
                            title: "Add member",
                            symbol: "person.badge.plus",
                            detail: "Create clean payer and owner options for subscriptions and protected purchases."
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NAME")
                                    .font(.system(.caption2, design: .rounded, weight: .bold))
                                    .foregroundStyle(PayGuardTheme.textSecondary)

                                TextField("Alex, Maya, You", text: $newMemberName)
                                    .textInputAutocapitalization(.words)
                                    .payGuardTextInputStyle()
                            }

                            Picker("Role", selection: $role) {
                                ForEach(MemberRole.allCases) { item in
                                    Text(item.label).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            Button("Add member") {
                                addMember()
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                            .disabled(trimmedMemberName.isEmpty)
                            .opacity(trimmedMemberName.isEmpty ? 0.6 : 1)
                        }
                        .padding(.horizontal, 20)

                        PayGuardPanel(
                            title: "Members",
                            symbol: "person.2.fill",
                            detail: "Each member can own services, pay bills, or simply stay visible in the shared picture."
                        ) {
                            if members.isEmpty {
                                Text("No family members yet. Add the first one above to start assigning ownership and payment responsibility.")
                                    .font(PayGuardTheme.captionFont)
                                    .foregroundStyle(PayGuardTheme.textSecondary)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                                        memberRow(member)

                                        if index < members.count - 1 {
                                            Divider()
                                                .overlay(PayGuardTheme.divider)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        PayGuardPanel(
                            title: "Shared insights",
                            symbol: "chart.bar.xaxis",
                            detail: "A quick operational view of what the household is carrying right now."
                        ) {
                            PayGuardKeyValueRow(
                                title: "Tracked subscriptions",
                                value: "\(subscriptions.filter { !$0.isArchived }.count)"
                            )
                            PayGuardKeyValueRow(
                                title: "Protected purchases",
                                value: "\(purchases.filter { !$0.isArchived }.count)"
                            )
                            PayGuardKeyValueRow(
                                title: "Shared monthly total",
                                value: householdSnapshot.monthlyTotal.currencyString(code: "EUR")
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 32)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionTitleView(
                            eyebrow: "Household",
                            title: "Family setup is part of PayGuard Pro.",
                            detail: "Unlock shared owners, payers, and member management when you are ready to organize a household."
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        PremiumLockedCard(
                            title: "Family management",
                            detail: "Create members, assign payers and owners, and unlock shared household summaries with Lifetime Pro.",
                            buttonTitle: "Unlock Pro"
                        ) {
                            premiumGate = .familyManagement
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .background(PayGuardBackdrop())
        .navigationTitle("Family")
        .payGuardNavigationChrome()
        .task {
            ensureFallbackMemberExistsIfNeeded()
        }
        .alert("Member name already exists", isPresented: Binding(
            get: { duplicateNameMessage != nil },
            set: { if !$0 { duplicateNameMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(duplicateNameMessage ?? "")
        }
        .sheet(item: $premiumGate) { gate in
            PremiumUpgradeSheet(gate: gate)
        }
    }

    private var overviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                PayGuardMetricBadge(title: "Members", value: "\(members.count)")
                PayGuardMetricBadge(title: "Monthly", value: householdSnapshot.monthlyTotal.currencyString(code: "EUR"))
                PayGuardMetricBadge(title: "Protected", value: householdSnapshot.protectedPurchaseValue.currencyString(code: "EUR"))
            }
            .padding(.horizontal, 20)
        }
    }

    private var trimmedMemberName: String {
        newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addMember() {
        guard !trimmedMemberName.isEmpty else { return }
        guard !members.contains(where: { $0.name.normalizedLookupKey == trimmedMemberName.normalizedLookupKey }) else {
            duplicateNameMessage = PMLocalized("Please choose a unique member name so payer and owner assignments stay unambiguous.")
            return
        }
        modelContext.insert(FamilyMember(name: trimmedMemberName, role: role))
        newMemberName = ""
        role = .adult
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(member.name)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(PayGuardTheme.textPrimary)
                    PayGuardTag(title: member.role.label)
                }

                Text(memberTotal(for: member.name).currencyString(code: "EUR"))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(PayGuardTheme.textSecondary)
            }

            Spacer()

            Button(role: .destructive) {
                delete(member)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PayGuardTheme.destructive)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(PayGuardTheme.destructive.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(member.name)")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(PayGuardTheme.surfaceSecondary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func memberTotal(for name: String) -> Decimal {
        memberTotals.first(where: { $0.name == name })?.total ?? 0
    }

    private func ensureFallbackMemberExistsIfNeeded() {
        guard members.isEmpty else { return }
        modelContext.insert(FamilyMember(name: "You", role: .owner))
    }

    private func delete(_ member: FamilyMember) {
        let fallback = fallbackMember(excluding: member)

        subscriptions.forEach { subscription in
            if subscription.ownerMemberID == member.id || subscription.ownerName.normalizedLookupKey == member.name.normalizedLookupKey {
                subscription.ownerMemberID = fallback.id
                subscription.ownerName = fallback.name
                subscription.updatedAt = .now
            }
            if subscription.payerMemberID == member.id || subscription.payerName.normalizedLookupKey == member.name.normalizedLookupKey {
                subscription.payerMemberID = fallback.id
                subscription.payerName = fallback.name
                subscription.updatedAt = .now
            }
        }

        purchases.forEach { purchase in
            if purchase.ownerMemberID == member.id || purchase.ownerName.normalizedLookupKey == member.name.normalizedLookupKey {
                purchase.ownerMemberID = fallback.id
                purchase.ownerName = fallback.name
                purchase.updatedAt = .now
            }
            if purchase.payerMemberID == member.id || purchase.payerName.normalizedLookupKey == member.name.normalizedLookupKey {
                purchase.payerMemberID = fallback.id
                purchase.payerName = fallback.name
                purchase.updatedAt = .now
            }
        }

        modelContext.delete(member)
    }

    private func fallbackMember(excluding deletedMember: FamilyMember) -> FamilyMember {
        if let existingYou = members.first(where: { $0.id != deletedMember.id && $0.name.normalizedLookupKey == "you" }) {
            return existingYou
        }

        if let firstOther = members.first(where: { $0.id != deletedMember.id }) {
            return firstOther
        }

        let created = FamilyMember(name: "You", role: .owner)
        modelContext.insert(created)
        return created
    }
}
