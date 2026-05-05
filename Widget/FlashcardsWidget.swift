// ─────────────────────────────────────────────────────────────────
// FlashcardsWidget.swift
// Add this file to your Widget Extension target (see WIDGET_SETUP.md)
// ─────────────────────────────────────────────────────────────────
import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct FlashcardsEntry: TimelineEntry {
    let date: Date
    let dueCount: Int
    let streak: Int
    let todayReviews: Int
}

// MARK: - Provider

struct FlashcardsProvider: TimelineProvider {
    let appGroupID = "group.com.flashcards.shared"

    func placeholder(in context: Context) -> FlashcardsEntry {
        FlashcardsEntry(date: Date(), dueCount: 12, streak: 5, todayReviews: 8)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlashcardsEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlashcardsEntry>) -> Void) {
        let e = entry()
        // Refresh at the top of the next hour (stale data for more than an hour is not useful)
        let nextRefresh = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [e], policy: .after(nextRefresh)))
    }

    private func entry() -> FlashcardsEntry {
        let defaults = UserDefaults(suiteName: appGroupID)
        return FlashcardsEntry(
            date: Date(),
            dueCount:     defaults?.integer(forKey: "widget.dueCount")      ?? 0,
            streak:       defaults?.integer(forKey: "widget.streak")        ?? 0,
            todayReviews: defaults?.integer(forKey: "widget.todayReviews")  ?? 0
        )
    }
}

// MARK: - Small widget view

struct SmallWidgetView: View {
    let entry: FlashcardsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "rectangle.stack.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.orange)
                    Text("\(entry.streak)d").font(.caption2.monospacedDigit()).foregroundStyle(.orange)
                }
            }

            Spacer()

            Text("\(entry.dueCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(entry.dueCount == 0 ? .green : .primary)
                .minimumScaleFactor(0.6)

            Text(entry.dueCount == 0 ? "All done!" : "cards due")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }
}

// MARK: - Medium widget view

struct MediumWidgetView: View {
    let entry: FlashcardsEntry

    var body: some View {
        HStack(spacing: 0) {
            // Due count panel
            VStack(alignment: .leading, spacing: 4) {
                Label("Due now", systemImage: "clock.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("\(entry.dueCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.dueCount == 0 ? .green : .primary)
                    .minimumScaleFactor(0.5)
                Text(entry.dueCount == 0 ? "All caught up" : "cards to review")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)

            Divider().padding(.vertical, 12)

            // Stats panel
            VStack(spacing: 12) {
                statCell(icon: "flame.fill", value: "\(entry.streak)d", label: "streak", tint: .orange)
                statCell(icon: "checkmark.circle.fill", value: "\(entry.todayReviews)", label: "today", tint: .green)
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 16)
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private func statCell(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint).font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.bold().monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock screen widget views (iOS 16+ accessory families)

struct AccessoryCircularView: View {
    let entry: FlashcardsEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: entry.dueCount == 0 ? "checkmark" : "rectangle.stack.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                Text("\(entry.dueCount)")
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .widgetAccentable()
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

struct AccessoryRectangularView: View {
    let entry: FlashcardsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.fill").widgetAccentable()
                Text("Flashcards").fontWeight(.semibold)
            }
            .font(.caption2)
            Text(entry.dueCount == 0
                 ? "All caught up"
                 : "\(entry.dueCount) card\(entry.dueCount == 1 ? "" : "s") due")
                .font(.headline.monospacedDigit())
                .widgetAccentable()
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                Text("\(entry.streak)d streak")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

struct AccessoryInlineView: View {
    let entry: FlashcardsEntry

    var body: some View {
        if entry.dueCount == 0 {
            Label("All caught up", systemImage: "checkmark").widgetAccentable()
        } else {
            Label("\(entry.dueCount) cards due", systemImage: "rectangle.stack.fill").widgetAccentable()
        }
    }
}

// MARK: - Widget declaration

struct FlashcardsWidget: Widget {
    let kind = "FlashcardsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlashcardsProvider()) { entry in
            FlashcardsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Flashcards")
        .description("See how many cards are due and keep your streak alive.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct FlashcardsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FlashcardsEntry

    var body: some View {
        switch family {
        case .systemSmall:           SmallWidgetView(entry: entry)
        case .systemMedium:          MediumWidgetView(entry: entry)
        case .accessoryCircular:     AccessoryCircularView(entry: entry)
        case .accessoryRectangular:  AccessoryRectangularView(entry: entry)
        case .accessoryInline:       AccessoryInlineView(entry: entry)
        default:                     SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Bundle entry point

@main
struct FlashcardsWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlashcardsWidget()
    }
}
