import AppIntents
import SwiftUI
import WidgetKit

@main
struct KakeiboWidgetBundle: WidgetBundle {
    var body: some Widget {
        SummaryWidget()
        NextBillWidget()
        AddEntryControl()
    }
}

// MARK: Timeline

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

// MARK: Budget widget (small, medium, Lock Screen)

struct SummaryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    private var snapshot: WidgetSnapshot {
        entry.snapshot ?? WidgetSnapshot(monthTitle: "", spent: 0, budget: 0, partnerOwed: 0, updatedAt: Date())
    }

    private var statusText: String {
        switch snapshot.paceStatus {
        case "over": return "Over budget"
        case "atRisk": return "Ahead of pace"
        default: return "On track"
        }
    }

    private var statusColor: Color {
        switch snapshot.paceStatus {
        case "over": return Palette.negativeText
        case "atRisk": return Palette.warning
        default: return Palette.positive
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(snapshot.budget > 0 ? "\(Yen.format(snapshot.left)) left" : "\(Yen.format(snapshot.spent)) spent")
        case .accessoryCircular:
            Gauge(value: min(snapshot.fraction, 1)) {
                Image(systemName: "plus")
            } currentValueLabel: {
                Image(systemName: "plus")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel("Budget used \(Int((snapshot.fraction * 100).rounded()))%, tap to log")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Kakeibo · " + String(snapshot.monthTitle.prefix(3)))
                    .font(.caption.weight(.semibold))
                Text(snapshot.budget > 0 ? "\(Yen.format(snapshot.left)) left" : "\(Yen.format(snapshot.spent)) spent")
                    .font(.headline)
                    .monospacedDigit()
                if snapshot.budget > 0 {
                    Gauge(value: min(snapshot.fraction, 1)) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
            }
        case .systemMedium:
            HStack(spacing: 14) {
                budget
                Link(destination: URL(string: "kakeibo://add")!) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                        Text("New entry")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 96)
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.accentFill))
                }
            }
        default:
            budget
        }
    }

    private var budget: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.monthTitle.isEmpty ? "KAKEIBO" : snapshot.monthTitle.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(Yen.format(snapshot.budget > 0 ? abs(snapshot.left) : snapshot.spent))
                .font(.title2.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(snapshot.left < 0 && snapshot.budget > 0 ? Palette.negativeText : Palette.textPrimary)
                .padding(.top, 2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if snapshot.budget > 0 {
                WidgetBudgetBar(fraction: snapshot.fraction, pace: snapshot.paceFraction)
                Text(family == .systemMedium ? (snapshot.alert ?? statusText) : statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(family == .systemMedium && snapshot.alert != nil ? Palette.negativeText : statusColor)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        guard snapshot.budget > 0 else { return "spent this month" }
        if snapshot.left < 0 { return "over budget" }
        if family == .systemMedium { return "left of \(Yen.format(snapshot.budget))" }
        if let perDay = snapshot.perDay, perDay > 0 { return "left · \(Yen.format(perDay))/day" }
        return "left"
    }
}

/// Budget bar with today's pace tick, sized for widgets.
struct WidgetBudgetBar: View {
    let fraction: Double
    let pace: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(fraction > 1 ? Palette.negative : Palette.accentData)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                if let pace {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.paceTick)
                        .frame(width: 2, height: 12)
                        .offset(x: geo.size.width * min(max(pace, 0), 1) - 1)
                }
            }
            .frame(width: geo.size.width, height: 6)
        }
        .frame(height: 6)
    }
}

struct SummaryWidget: Widget {
    let kind = "KakeiboSummary"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(Palette.card, for: .widget)
                .widgetURL(URL(string: "kakeibo://add"))
        }
        .configurationDisplayName("Budget")
        .description("What's left this month against today's pace. Tap to add an entry.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: Next card bill

struct NextBillWidgetView: View {
    let entry: SummaryEntry

    var body: some View {
        if let bill = entry.snapshot?.nextBill {
            VStack(alignment: .leading, spacing: 0) {
                Text("NEXT CARD BILL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill((CardColor(rawValue: bill.colorKey) ?? .blue).color)
                        .frame(width: 14, height: 10)
                    Text(bill.cardName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.top, 4)
                Text(Yen.format(bill.amount))
                    .font(.title2.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(bill.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 4)
                if bill.shortfall > 0 {
                    Label("\(Yen.format(bill.shortfall)) short", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.warning)
                        .lineLimit(1)
                } else if let payer = bill.payerName {
                    Label("\(payer) covers it", systemImage: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.positive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT CARD BILL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("Nothing due")
                    .font(.headline)
                Text("Bills show up when a statement closes.")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NextBillWidget: Widget {
    let kind = "KakeiboNextBill"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryProvider()) { entry in
            NextBillWidgetView(entry: entry)
                .containerBackground(Palette.card, for: .widget)
                .widgetURL(URL(string: "kakeibo://add"))
        }
        .configurationDisplayName("Next card bill")
        .description("The next card payment and whether the paying account covers it.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: Control Center / Action Button

struct AddEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.matisse.kakeibo.add") {
            ControlWidgetButton(action: OpenAddEntryIntent()) {
                Label("Log Expense", systemImage: "yensign.circle")
            }
        }
        .displayName("Log Expense")
        .description("Opens Kakeibo ready to log an expense.")
    }
}
