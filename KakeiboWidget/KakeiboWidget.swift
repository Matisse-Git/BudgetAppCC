import AppIntents
import SwiftUI
import WidgetKit

@main
struct KakeiboWidgetBundle: WidgetBundle {
    var body: some Widget {
        SummaryWidget()
        AddEntryControl()
    }
}

// MARK: Home / Lock Screen widget

struct SummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let entry = SummaryEntry(date: Date(), snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct SummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    private var snapshot: WidgetSnapshot {
        entry.snapshot ?? WidgetSnapshot(monthTitle: "", spent: 0, budget: 0, partnerOwed: 0, updatedAt: Date())
    }

    private var left: Int { snapshot.budget - snapshot.spent }
    private var fraction: Double {
        snapshot.budget > 0 ? min(Double(snapshot.spent) / Double(snapshot.budget), 1) : 0
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            if snapshot.budget > 0 {
                Text("¥ \(Yen.format(left)) left")
            } else {
                Text("¥ \(Yen.format(snapshot.spent)) spent")
            }
        case .accessoryCircular:
            Gauge(value: fraction) {
                Image(systemName: "plus")
            } currentValueLabel: {
                Image(systemName: "plus")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Kakeibo").font(.headline)
                Text("\(Yen.format(snapshot.spent)) spent")
                if snapshot.budget > 0 {
                    Text(left >= 0 ? "\(Yen.format(left)) left" : "\(Yen.format(-left)) over")
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snapshot.monthTitle.isEmpty ? "Kakeibo" : snapshot.monthTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                }
                Text(Yen.format(snapshot.spent))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                if snapshot.budget > 0 {
                    ProgressView(value: fraction)
                        .tint(left < 0 ? Color.red : Color.green)
                    Text(left >= 0 ? "\(Yen.format(left)) left" : "\(Yen.format(-left)) over")
                        .font(.caption)
                        .foregroundStyle(left < 0 ? Color.red : Color.secondary)
                }
                Spacer(minLength: 0)
                if snapshot.partnerOwed > 0 {
                    Text("Owed to you \(Yen.format(snapshot.partnerOwed))")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }
            }
        }
    }
}

struct SummaryWidget: Widget {
    let kind = "KakeiboSummary"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "kakeibo://add"))
        }
        .configurationDisplayName("Kakeibo")
        .description("This month's spending. Tap to add an entry.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Control Center / Action Button

struct AddEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.matisse.kakeibo.add") {
            ControlWidgetButton(action: OpenAddEntryIntent()) {
                Label("Add entry", systemImage: "yensign.circle")
            }
        }
        .displayName("Add Kakeibo entry")
        .description("Opens Kakeibo ready to add an entry.")
    }
}
