import Charts
import SwiftData
import SwiftUI

/// This month's split by category, the last six months, and every category's budget.
struct BudgetsView: View {
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    /// Categories without a budget are tucked away until asked for.
    @State private var showAll = DemoMode.screen == "budgets-all"

    var body: some View {
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let summary = MonthSummary(ledger: ledger, month: Date())
        let shown = categories.filter { $0.kind == .expense && (!$0.isArchived || (summary.spending[$0.id] ?? 0) != 0) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    SplitCard(summary: summary, categories: shown)
                    VStack(spacing: 10) {
                        SectionHeader(title: "Last 6 months")
                        MonthsChart(totals: ledger.monthTotals(count: 6), budget: summary.budget)
                    }
                    VStack(spacing: 10) {
                        SectionHeader(title: "Categories")
                        CategoriesCard(listing: BudgetListing(categories: categories, spending: summary.spending),
                                       spending: summary.spending, showAll: $showAll)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.groupedBackground)
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit") {
                        CategoriesView()
                    }
                }
            }
        }
    }
}

/// Categories with a budget, then a "See all categories" row that reveals the ones without.
private struct CategoriesCard: View {
    let listing: BudgetListing
    let spending: [UUID: Int]
    @Binding var showAll: Bool

    var body: some View {
        let expanded = showAll || listing.showsEverything
        let rows = expanded ? listing.budgeted + listing.unbudgeted : listing.budgeted
        RowsCard {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, category in
                if index > 0 { RowDivider(inset: 48) }
                CategoryBudgetRow(category: category, spent: spending[category.id] ?? 0, compact: true)
                    .padding(.vertical, 12)
            }
            if !listing.showsEverything && !listing.unbudgeted.isEmpty {
                RowDivider(inset: 0)
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { showAll.toggle() }
                } label: {
                    HStack {
                        Text(showAll ? "Show budgeted only" : "See all categories")
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        if !showAll {
                            Text(listing.unbudgetedSpent != 0
                                 ? "\(Yen.format(listing.unbudgetedSpent)) with no budget"
                                 : "\(listing.unbudgeted.count) with no budget")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showAll ? 180 : 0))
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One bar split by category, measured against the whole budget.
private struct SplitCard: View {
    let summary: MonthSummary
    let categories: [BudgetCategory]

    private struct Segment: Identifiable {
        let id: String
        let title: String
        let value: Int
        let color: Color
    }

    private var segments: [Segment] {
        var named: [Segment] = []
        var rest = 0
        let sorted = categories.sorted { (summary.spending[$0.id] ?? 0) > (summary.spending[$1.id] ?? 0) }
        for category in sorted {
            let value = summary.spending[category.id] ?? 0
            guard value > 0 else { continue }
            let look = CategoryLook.of(category)
            if look.isHighlighted {
                named.append(Segment(id: category.id.uuidString, title: category.name, value: value, color: look.tint))
            } else {
                rest += value
            }
        }
        if rest > 0 {
            named.append(Segment(id: "rest", title: "Everything else", value: rest, color: .categoryNeutral))
        }
        return named
    }

    var body: some View {
        let parts = segments
        let scale = max(summary.budget, summary.spent, 1)
        let used = summary.budget > 0 ? Double(summary.spent) / Double(summary.budget) : 0
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Date().formatted(.dateTime.month(.wide))) so far")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(Yen.format(summary.spent))
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                }
                Spacer()
                if summary.budget > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("of \(Yen.format(summary.budget))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(Int((used * 100).rounded()))% used")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(used > 1 ? Color.red : Color.green)
                    }
                    .monospacedDigit()
                }
            }

            GeometryReader { geo in
                let gaps = CGFloat(max(parts.count - 1, 0)) * 2
                let width = max(geo.size.width - gaps, 0)
                HStack(spacing: 2) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(part.color)
                            .frame(width: width * CGFloat(part.value) / CGFloat(scale))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.barTrack)
                .clipShape(Capsule())
            }
            .frame(height: 14)
            .accessibilityHidden(true)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 10) {
                ForEach(parts) { part in
                    legendRow(part.title, part.value, color: part.color)
                }
                if summary.budget > 0 {
                    legendRow(summary.left >= 0 ? "Left" : "Over", abs(summary.left),
                              color: summary.left >= 0 ? Color.barTrack : Color.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.card))
    }

    private func legendRow(_ title: String, _ value: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(Yen.format(value)).monospacedDigit()
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }
}

/// Monthly totals as bars, with the budget as a dashed line. Tap or drag to read a month.
private struct MonthsChart: View {
    let totals: [MonthTotal]
    let budget: Int
    @State private var selected: String?

    private func label(_ total: MonthTotal) -> String {
        total.start.formatted(.dateTime.month(.abbreviated))
    }

    private var shown: MonthTotal? {
        if let selected, let match = totals.first(where: { label($0) == selected }) { return match }
        return totals.last
    }

    var body: some View {
        let top = max(budget, totals.map(\.spent).max() ?? 0, 1_000)
        VStack(alignment: .leading, spacing: 12) {
            if let shown {
                HStack(spacing: 4) {
                    Text(shown.isCurrent ? "\(label(shown)) so far" : label(shown)).foregroundStyle(.secondary)
                    Text(Yen.format(shown.spent)).fontWeight(.semibold)
                    if budget > 0 && shown.spent > budget {
                        Text("· \(Yen.format(shown.spent - budget)) over").foregroundStyle(Color.shortfall)
                    }
                }
                .font(.footnote)
                .monospacedDigit()
            }
            Chart {
                ForEach(totals) { total in
                    BarMark(
                        x: .value("Month", label(total)),
                        y: .value("Spent", total.spent),
                        width: .fixed(28)
                    )
                    .foregroundStyle(budget > 0 && total.spent > budget ? Color.red : Color.accentColor)
                    .opacity(barOpacity(total))
                    .cornerRadius(6)
                }
                if budget > 0 {
                    RuleMark(y: .value("Budget", budget))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartYScale(domain: 0...Int(Double(top) * 1.1))
            .chartYAxis {
                AxisMarks(position: .trailing, values: budget > 0 ? [0, budget] : [0]) { value in
                    AxisValueLabel {
                        if let yen = value.as(Int.self) {
                            Text(yen == 0 ? "0" : Yen.short(yen))
                        }
                    }
                }
            }
            .chartXSelection(value: $selected)
            .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
            .frame(height: 170)

            HStack(spacing: 16) {
                legend("Under budget", color: .accentColor, opacity: 1)
                legend("Over budget", color: .red, opacity: 1)
                legend("So far", color: .accentColor, opacity: 0.45)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.card))
    }

    private func barOpacity(_ total: MonthTotal) -> Double {
        let base = total.isCurrent ? 0.45 : 1
        guard let selected else { return base }
        return label(total) == selected ? base : base * 0.5
    }

    private func legend(_ title: String, color: Color, opacity: Double) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).opacity(opacity).frame(width: 10, height: 10)
            Text(title)
        }
    }
}
