//
//  PayGuardPremiumWidgets.swift
//  PayGuardWidget
//
//  Created by Ali Ozkul on 02.05.26.
//

import SwiftUI
import WidgetKit

private struct PayGuardWidgetSnapshotPayload: Codable {
    let updatedAt: Date
    let isLifetimeUnlocked: Bool
    let hasData: Bool
    let monthlyTotalLabel: String
    let monthlyTotalDisplay: String
    let activePlansLabel: String
    let activePlanCount: Int
    let protectedLabel: String
    let protectedCount: Int
    let attentionLabel: String
    let attentionCount: Int
    let nextChargeLabel: String
    let nextChargeTitle: String?
    let nextChargeDateLabel: String?
    let nextChargeAmountDisplay: String?
    let focusLabel: String
    let focusTitle: String
    let focusDetail: String
    let lockedStateTitle: String
    let lockedStateDetail: String
    let lockedStateBadgeTitle: String
    let emptyStateTitle: String
    let emptyStateDetail: String

    static var placeholder: PayGuardWidgetSnapshotPayload {
        PayGuardWidgetSnapshotPayload(
            updatedAt: .now,
            isLifetimeUnlocked: true,
            hasData: true,
            monthlyTotalLabel: "Monthly total",
            monthlyTotalDisplay: "EUR 42.99",
            activePlansLabel: "Active plans",
            activePlanCount: 4,
            protectedLabel: "Protected",
            protectedCount: 2,
            attentionLabel: "Needs review",
            attentionCount: 1,
            nextChargeLabel: "Next charge",
            nextChargeTitle: "Spotify Family",
            nextChargeDateLabel: "Tomorrow",
            nextChargeAmountDisplay: "EUR 10.99",
            focusLabel: "Top priority",
            focusTitle: "Review Spotify Family before renewal",
            focusDetail: "Charges tomorrow for EUR 10.99.",
            lockedStateTitle: "Premium widgets",
            lockedStateDetail: "Unlock Lifetime Pro to place live subscription insights, next charges, and action cues on your Home Screen.",
            lockedStateBadgeTitle: "Unlock in app",
            emptyStateTitle: "No tracked data yet",
            emptyStateDetail: "Add your first subscription or protected purchase to see live widget insights."
        )
    }

    static var empty: PayGuardWidgetSnapshotPayload {
        PayGuardWidgetSnapshotPayload(
            updatedAt: .now,
            isLifetimeUnlocked: false,
            hasData: false,
            monthlyTotalLabel: "Monthly total",
            monthlyTotalDisplay: "EUR 0.00",
            activePlansLabel: "Active plans",
            activePlanCount: 0,
            protectedLabel: "Protected",
            protectedCount: 0,
            attentionLabel: "Needs review",
            attentionCount: 0,
            nextChargeLabel: "Next charge",
            nextChargeTitle: nil,
            nextChargeDateLabel: nil,
            nextChargeAmountDisplay: nil,
            focusLabel: "Top priority",
            focusTitle: "No tracked data yet",
            focusDetail: "Add your first subscription or protected purchase to see live widget insights.",
            lockedStateTitle: "Premium widgets",
            lockedStateDetail: "Unlock Lifetime Pro to place live subscription insights, next charges, and action cues on your Home Screen.",
            lockedStateBadgeTitle: "Unlock in app",
            emptyStateTitle: "No tracked data yet",
            emptyStateDetail: "Add your first subscription or protected purchase to see live widget insights."
        )
    }
}

private enum PayGuardWidgetStore {
    static let appGroupID = "group.Ali-Orkun-Ozkul.PayGuard.shared"
    static let snapshotKey = "paymind.widget.snapshot"

    static func loadSnapshot() -> PayGuardWidgetSnapshotPayload {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(PayGuardWidgetSnapshotPayload.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}

private struct PayGuardWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PayGuardWidgetSnapshotPayload
}

private struct PayGuardWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PayGuardWidgetEntry {
        PayGuardWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PayGuardWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? PayGuardWidgetSnapshotPayload.placeholder : PayGuardWidgetStore.loadSnapshot()
        completion(PayGuardWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PayGuardWidgetEntry>) -> Void) {
        let entry = PayGuardWidgetEntry(date: .now, snapshot: PayGuardWidgetStore.loadSnapshot())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

private struct PremiumWidgetSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .containerBackground(for: .widget) {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.10, blue: 0.18),
                            Color(red: 0.08, green: 0.25, blue: 0.38),
                            Color(red: 0.11, green: 0.47, blue: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 160, height: 160)
                        .offset(x: 90, y: -70)
                        .blur(radius: 10)
                }
            }
    }
}

private struct WidgetHeader: View {
    let updatedAt: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PayGuard")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(updatedAt, style: .time)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct EmptyWidgetState: View {
    let title: String
    let detail: String
    let lineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(lineLimit)
        }
    }
}

private struct LockedWidgetState: View {
    let title: String
    let detail: String
    let badgeTitle: String
    let lineLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "lock.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(lineLimit)

            Text(badgeTitle)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.12), in: Capsule())
        }
    }
}

private struct OverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: PayGuardWidgetEntry

    var body: some View {
        PremiumWidgetSurface {
            Group {
                switch family {
                case .systemMedium:
                    mediumView
                default:
                    smallView
                }
            }
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(updatedAt: entry.snapshot.updatedAt)

            if !entry.snapshot.isLifetimeUnlocked {
                Spacer(minLength: 0)
                LockedWidgetState(
                    title: entry.snapshot.lockedStateTitle,
                    detail: entry.snapshot.lockedStateDetail,
                    badgeTitle: entry.snapshot.lockedStateBadgeTitle,
                    lineLimit: 5
                )
                Spacer(minLength: 0)
            } else if entry.snapshot.hasData {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.snapshot.monthlyTotalLabel.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(entry.snapshot.monthlyTotalDisplay)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                }

                HStack(spacing: 10) {
                    StatPill(title: entry.snapshot.activePlansLabel, value: "\(entry.snapshot.activePlanCount)")
                    StatPill(title: entry.snapshot.attentionLabel, value: "\(entry.snapshot.attentionCount)")
                }

                if let nextChargeTitle = entry.snapshot.nextChargeTitle {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.snapshot.nextChargeLabel.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(nextChargeTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text([entry.snapshot.nextChargeDateLabel, entry.snapshot.nextChargeAmountDisplay].compactMap { $0 }.joined(separator: " • "))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            } else {
                Spacer(minLength: 0)
                EmptyWidgetState(
                    title: entry.snapshot.emptyStateTitle,
                    detail: entry.snapshot.emptyStateDetail,
                    lineLimit: 4
                )
                Spacer(minLength: 0)
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                WidgetHeader(updatedAt: entry.snapshot.updatedAt)

                if !entry.snapshot.isLifetimeUnlocked {
                    LockedWidgetState(
                        title: entry.snapshot.lockedStateTitle,
                        detail: entry.snapshot.lockedStateDetail,
                        badgeTitle: entry.snapshot.lockedStateBadgeTitle,
                        lineLimit: 5
                    )
                } else if entry.snapshot.hasData {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.snapshot.monthlyTotalLabel.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(entry.snapshot.monthlyTotalDisplay)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 10) {
                        StatPill(title: entry.snapshot.activePlansLabel, value: "\(entry.snapshot.activePlanCount)")
                        StatPill(title: entry.snapshot.protectedLabel, value: "\(entry.snapshot.protectedCount)")
                        StatPill(title: entry.snapshot.attentionLabel, value: "\(entry.snapshot.attentionCount)")
                    }
                } else {
                    EmptyWidgetState(
                        title: entry.snapshot.emptyStateTitle,
                        detail: entry.snapshot.emptyStateDetail,
                        lineLimit: 4
                    )
                }
            }

            Divider()
                .overlay(.white.opacity(0.18))

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.snapshot.nextChargeLabel.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                if let nextChargeTitle = entry.snapshot.nextChargeTitle {
                    Text(nextChargeTitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(entry.snapshot.nextChargeDateLabel ?? "")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                    Text(entry.snapshot.nextChargeAmountDisplay ?? "")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    EmptyWidgetState(
                        title: entry.snapshot.emptyStateTitle,
                        detail: entry.snapshot.emptyStateDetail,
                        lineLimit: 4
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: PayGuardWidgetEntry

    var body: some View {
        PremiumWidgetSurface {
            Group {
                switch family {
                case .systemMedium:
                    mediumView
                default:
                    smallView
                }
            }
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(updatedAt: entry.snapshot.updatedAt)

            if !entry.snapshot.isLifetimeUnlocked {
                Spacer(minLength: 0)
                LockedWidgetState(
                    title: entry.snapshot.lockedStateTitle,
                    detail: entry.snapshot.lockedStateDetail,
                    badgeTitle: entry.snapshot.lockedStateBadgeTitle,
                    lineLimit: 5
                )
                Spacer(minLength: 0)
            } else if entry.snapshot.hasData {
                Text(entry.snapshot.focusLabel.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Text(entry.snapshot.focusTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Text(entry.snapshot.focusDetail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(4)
            } else {
                Spacer(minLength: 0)
                EmptyWidgetState(
                    title: entry.snapshot.emptyStateTitle,
                    detail: entry.snapshot.emptyStateDetail,
                    lineLimit: 4
                )
                Spacer(minLength: 0)
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(updatedAt: entry.snapshot.updatedAt)

            if !entry.snapshot.isLifetimeUnlocked {
                LockedWidgetState(
                    title: entry.snapshot.lockedStateTitle,
                    detail: entry.snapshot.lockedStateDetail,
                    badgeTitle: entry.snapshot.lockedStateBadgeTitle,
                    lineLimit: 5
                )
            } else if entry.snapshot.hasData {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.snapshot.focusLabel.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(entry.snapshot.focusTitle)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                        Text(entry.snapshot.focusDetail)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(4)
                    }

                    VStack(spacing: 10) {
                        StatPill(title: entry.snapshot.attentionLabel, value: "\(entry.snapshot.attentionCount)")
                        StatPill(title: entry.snapshot.protectedLabel, value: "\(entry.snapshot.protectedCount)")
                    }
                    .frame(width: 110)
                }
            } else {
                EmptyWidgetState(
                    title: entry.snapshot.emptyStateTitle,
                    detail: entry.snapshot.emptyStateDetail,
                    lineLimit: 4
                )
            }
        }
    }
}

struct PayGuardOverviewWidget: Widget {
    private let kind = "PayGuardOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PayGuardWidgetProvider()) { entry in
            OverviewWidgetView(entry: entry)
        }
        .configurationDisplayName("PayGuard Overview")
        .description("See your monthly total, active plans, and next charge at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PayGuardFocusWidget: Widget {
    private let kind = "PayGuardFocusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PayGuardWidgetProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("PayGuard Focus")
        .description("Keep the most important renewal or protection task on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PayGuardPremiumWidgets_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OverviewWidgetView(
                entry: PayGuardWidgetEntry(date: .now, snapshot: .placeholder)
            )
            .previewContext(WidgetPreviewContext(family: .systemSmall))

            FocusWidgetView(
                entry: PayGuardWidgetEntry(date: .now, snapshot: .placeholder)
            )
            .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
