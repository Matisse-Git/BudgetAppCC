import Charts
import SwiftData
import SwiftUI

/// One category in one month (Category artboard): spent against budget and today's pace, a nudge when
/// it's over, the month's running total against last month, the last six months, and its entries.
struct CategoryDetailView: View {
    let category: BudgetCategory
    /// Any day in the month shown.
    let month: Date

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @State private var editing = false

    var body: some View {
        let now = Date()
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let pace = BudgetPace(ledger: ledger, month: month, now: now)
        let interval = pace.interval
        let spent = ledger.spendingByCategory(in: interval)[category.id] ?? 0
        let budget = category.isArchived ? 0 : category.monthlyBudget
        let item = BudgetPace.categoryPace(category, spent: spent, elapsed: pace.daysElapsed, days: pace.daysInMonth, previous: 0)
        let monthEntries = entries.filter { $0.categoryID == category.id && $0.kind == .expense && interval.contains($0.date) }
        let lookup = Lookup(accounts: accounts, categories: categories)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(spent: spent, budget: budget, item: item, pace: pace)
                if budget > 0 && spent > budget {
                    coverCard(over: spent - budget, pace: pace)
                        .padding(.top, 16)
                }
                throughTheMonth(ledger: ledger, interval: interval, pace: pace, budget: budget)
                    .padding(.top, 16)
                lastSixMonths(ledger: ledger, budget: budget)
                    .padding(.top, 16)
                entriesSection(monthEntries, lookup: lookup, monthName: interval.start.formatted(.dateTime.month(.wide)))
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
        }
        .kScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            CategoryEditView(category: category, kind: category.kind)
        }
    }

    // MARK: Sections

    private func header(spent: Int, budget: Int, item: CategoryPace, pace: BudgetPace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CategoryIcon(category: category, size: 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text(category.name)
                        .font(.title2.bold())
                        .foregroundStyle(Palette.textPrimary)
                    Text(budget > 0 ? "Budget \(Yen.format(budget)) a month" : "No monthly budget")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Yen.format(spent))
                    .font(.kDetailAmount)
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text("in \(pace.interval.start.formatted(.dateTime.month(.wide)))")
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.top, 12)
            if budget > 0 {
                Text(spent > budget ? "\(Yen.format(spent - budget)) over budget" : "\(Yen.format(budget - spent)) left")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(spent > budget ? Palette.negativeText : (item.status == .atRisk ? Palette.warning : Palette.positive))
                BudgetBar(fraction: item.fraction, pace: pace.isCurrentMonth ? item.paceFraction : nil,
                          tint: CategoryLook.of(category).tint)
                    .padding(.top, 12)
                HStack {
                    Text("\(Int((item.fraction * 100).rounded()))% used")
                    Spacer()
                    if pace.isCurrentMonth {
                        Text("Today's pace: \(Yen.format(item.pace))")
                    }
                }
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 6)
            }
        }
    }

    /// Not every option on the canvas is here yet: moving budget between categories needs per-month
    /// budgets, which the data doesn't have. Raising the budget is.
    private func coverCard(over: Int, pace: BudgetPace) -> some View {
        let roomiest = pace.onTrack.filter { $0.category.id != category.id }.max { $0.left < $1.left }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cover the \(Yen.format(over))")
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(roomiest.map { "\($0.category.name) still has \(Yen.format($0.left)) left this month. Spend less there, or raise this budget." }
                     ?? "Raise this budget if it was set too low.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Raise budget") { editing = true }
                .buttonStyle(PillButtonStyle(height: 42))
        }
        .kCard()
    }

    private struct DayPoint: Identifiable {
        let day: Int
        let value: Int
        let series: String
        var id: String { "\(series)-\(day)" }
    }

    private func throughTheMonth(ledger: Ledger, interval: DateInterval, pace: BudgetPace, budget: Int) -> some View {
        let calendar = Calendar.kakeibo
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let current = ledger.cumulativeSpending(in: interval, until: pace.isCurrentMonth ? endOfToday : nil, categoryID: category.id)
        let previousStart = pace.previousStart
        let previous = ledger.cumulativeSpending(in: Ledger.monthInterval(containing: previousStart), categoryID: category.id)
        let monthName = interval.start.formatted(.dateTime.month(.wide))
        let previousName = previousStart.formatted(.dateTime.month(.wide))
        let sameDay = min(current.count, previous.count)
        let points = current.enumerated().map { DayPoint(day: $0.offset + 1, value: $0.element, series: monthName) }
            + previous.enumerated().map { DayPoint(day: $0.offset + 1, value: $0.element, series: previousName) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Through the month").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                if sameDay > 0 {
                    Text("\(pace.comparisonLabel()): \(Yen.format(previous[sameDay - 1]))")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Day", point.day), y: .value("Spent", point.value), series: .value("Month", point.series))
                        .foregroundStyle(point.series == monthName ? CategoryLook.of(category).tint : Hue.gray.color)
                        .lineStyle(StrokeStyle(lineWidth: point.series == monthName ? 2.5 : 2, lineCap: .round, lineJoin: .round))
                }
                if budget > 0 {
                    RuleMark(y: .value("Budget", budget))
                        .foregroundStyle(Palette.textPrimary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Budget").font(.caption2).foregroundStyle(Palette.textSecondary)
                        }
                }
            }
            .chartXScale(domain: 1...max(pace.daysInMonth, 2))
            .chartXAxis { AxisMarks(values: [1, 8, 15, 22, 29]) { _ in AxisValueLabel() } }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(Palette.separator)
                    AxisValueLabel { if let yen = value.as(Int.self) { Text(yen == 0 ? "¥0" : Yen.short(yen)) } }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 160)
            HStack(spacing: 16) {
                HStack(spacing: 6) { Capsule().fill(CategoryLook.of(category).tint).frame(width: 16, height: 3); Text(monthName) }
                HStack(spacing: 6) { Capsule().fill(Hue.gray.color).frame(width: 16, height: 3); Text(previousName) }
            }
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
        }
        .kCard()
    }

    private func lastSixMonths(ledger: Ledger, budget: Int) -> some View {
        let totals = ledger.monthTotals(count: 6, now: month, categoryID: category.id)
        // The month in progress would drag the average down.
        let full = totals.filter { !Ledger.monthInterval(containing: Date()).contains($0.start) }
        let average = full.isEmpty ? 0 : full.reduce(0) { $0 + $1.spent } / full.count
        let overCount = budget > 0 ? totals.filter { $0.spent > budget }.count : 0
        return VStack(alignment: .leading, spacing: 0) {
            Text("Last 6 months").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            Text(budget > 0 ? "Average \(Yen.format(average)) · over budget in \(overCount) of 6 months" : "Average \(Yen.format(average))")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
            Chart {
                ForEach(totals) { total in
                    BarMark(x: .value("Month", total.start.formatted(.dateTime.month(.abbreviated))),
                            y: .value("Spent", total.spent), width: .fixed(28))
                        .foregroundStyle(budget > 0 && total.spent > budget ? Palette.negative : CategoryLook.of(category).tint)
                        .opacity(total.isCurrent ? 1 : 0.7)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text(String(Yen.short(total.spent).dropFirst()))
                                .font(.caption2)
                                .foregroundStyle(Palette.textSecondary)
                        }
                }
                if budget > 0 {
                    RuleMark(y: .value("Budget", budget))
                        .foregroundStyle(Palette.textPrimary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
            .padding(.top, 12)
        }
        .kCard()
    }

    @ViewBuilder
    private func entriesSection(_ items: [Entry], lookup: Lookup, monthName: String) -> some View {
        let total = items.reduce(0) { $0 + ($1.isRefund ? -$1.amount : $1.myShare) }
        let average = items.isEmpty ? 0 : total / items.count
        SectionCaps(title: monthName,
                    trailing: items.isEmpty ? nil : "\(items.count) \(items.count == 1 ? "entry" : "entries") · avg \(Yen.format(average))")
            .padding(.top, Metrics.sectionSpacing)
        if items.isEmpty {
            Text("Nothing spent here this month.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .kCard()
                .padding(.top, 8)
        } else {
            CardList {
                ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { ListDivider(inset: 16) }
                    NavigationLink {
                        TransactionDetailView(entry: entry)
                    } label: {
                        CategoryEntryRow(entry: entry, lookup: lookup, partnerName: partnerName)
                    }
                    .buttonStyle(.plain)
                }
                if items.count > 4 {
                    ListDivider(inset: 16)
                    NavigationLink {
                        CategoryEntriesView(title: "\(category.name) · \(monthName)", items: items)
                    } label: {
                        HStack {
                            Text("Show all \(items.count)").foregroundStyle(Palette.accentTint)
                            Spacer()
                            Chevron()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: Metrics.compactRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }
}

/// An entry inside a category: no icon (the page is the category), date and account underneath.
struct CategoryEntryRow: View {
    let entry: Entry
    let lookup: Lookup
    var partnerName = SettingsKey.defaultPartnerName

    var body: some View {
        let look = EntryPresentation(entry: entry, lookup: lookup, partnerName: partnerName)
        KRow(look.title, subtitle: "\(BillingText.day(entry.date)) · \(look.account?.name ?? "No account")") {
            EmptyView()
        } trailing: {
            Text(look.amountText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(look.amountColor)
        }
    }
}

struct CategoryEntriesView: View {
    let title: String
    let items: [Entry]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName

    var body: some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        List(items) { entry in
            CategoryEntryRow(entry: entry, lookup: lookup, partnerName: partnerName)
                .background {
                    NavigationLink {
                        TransactionDetailView(entry: entry)
                    } label: {
                        EmptyView()
                    }
                    .opacity(0)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .kScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
