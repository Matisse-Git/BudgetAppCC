import Charts
import SwiftData
import SwiftUI

struct HomeView: View {
    @Binding var showAdd: Bool
    @Binding var tab: AppTab

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @AppStorage(SettingsKey.homeSectionOrder) private var sectionOrder = HomeSection.defaultOrder
    @AppStorage(SettingsKey.homeHiddenSections) private var hiddenSections = ""
    @State private var monthOffset = 0
    @State private var showTransfer = false
    @State private var editingHome = false
    @State private var editing: Entry?

    private var monthDate: Date {
        Calendar.kakeibo.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    var body: some View {
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let summary = MonthSummary(ledger: ledger, month: monthDate)
        let hidden = HomeSection.hidden(from: hiddenSections)
        let sections = HomeSection.order(from: sectionOrder).filter { !hidden.contains($0) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    HeroView(summary: summary, monthName: monthDate.formatted(.dateTime.month(.wide)))
                    SpendingChart(summary: summary)
                    quickActions
                    ForEach(sections) { section in
                        sectionView(section, ledger: ledger, summary: summary)
                    }
                    Button {
                        editingHome = true
                    } label: {
                        Label("Edit Home", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .background(Capsule().fill(Color.card))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.groupedBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { monthPicker }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showTransfer) {
                EntryEditorView(mode: .new, initialKind: .transfer)
            }
            .sheet(isPresented: $editingHome) {
                EditHomeView(order: $sectionOrder, hidden: $hiddenSections)
            }
            .sheet(item: $editing) { entry in
                EntryEditorRouter(entry: entry)
            }
        }
    }

    // MARK: Header

    private var monthPicker: some View {
        HStack(spacing: 4) {
            Button {
                Haptics.selection()
                withAnimation { monthOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            .accessibilityLabel("Previous month")
            Text(monthDate.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 130)
            Button {
                Haptics.selection()
                withAnimation { monthOffset += 1 }
            } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
            .disabled(monthOffset >= 0)
            .accessibilityLabel("Next month")
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        let reviewCount = entries.filter { ($0.kind == .payoff && !$0.isConfirmed) || $0.needsReview }.count
        return HStack(alignment: .top, spacing: 8) {
            Button {
                showAdd = true
            } label: {
                QuickActionLabel(title: "Add", symbol: "plus", prominent: true)
            }
            Button {
                showTransfer = true
            } label: {
                QuickActionLabel(title: "Transfer", symbol: "arrow.left.arrow.right")
            }
            NavigationLink {
                PartnerView()
            } label: {
                QuickActionLabel(title: "Settle up", symbol: "heart")
            }
            NavigationLink {
                ReviewListView()
            } label: {
                QuickActionLabel(title: "Review", symbol: "checklist", badge: reviewCount)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionView(_ section: HomeSection, ledger: Ledger, summary: MonthSummary) -> some View {
        switch section {
        case .bills:
            if monthOffset == 0 {
                BillsCard(reminders: Billing.reminders(ledger: ledger))
            }
        case .recent:
            recentSection
        case .budgets:
            BudgetsPreview(categories: categories, summary: summary) { tab = .budgets }
        case .partner:
            partnerRow(owed: ledger.partnerOwed)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        let recent = Array(entries.prefix(3))
        if !recent.isEmpty {
            VStack(spacing: 10) {
                SectionHeader(title: "Recent") {
                    Button("See all") { tab = .activity }
                }
                RowsCard {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider() }
                        Button {
                            editing = entry
                        } label: {
                            EntryRow(entry: entry, lookup: lookup, partnerName: partnerName)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func partnerRow(owed: Int) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: "heart", tint: .pink, size: 40, circle: true)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if owed > 0 {
                        Text("\(partnerName) owes you")
                    } else if owed < 0 {
                        Text("\(partnerName) has paid back extra")
                    } else {
                        Text("\(partnerName): all settled")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text(Yen.format(abs(owed))).font(.title3.weight(.semibold)).monospacedDigit()
            }
            Spacer()
            NavigationLink {
                PartnerView()
            } label: {
                Text("Settle up")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.tileFill))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.card))
    }
}

// MARK: - Hero

private struct HeroView: View {
    let summary: MonthSummary
    let monthName: String

    var body: some View {
        VStack(spacing: 6) {
            Text(summary.today == nil ? "Spent in \(monthName)" : "Spent this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Yen.format(summary.spent))
                .font(.system(size: 50, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if summary.budget > 0 {
                HStack(spacing: 8) {
                    let over = summary.left < 0
                    Text(over ? "\(Yen.format(-summary.left)) over" : "\(Yen.format(summary.left)) left")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(over ? Color.red : Color.green)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill((over ? Color.red : Color.green).opacity(0.16)))
                    if summary.perDay > 0 {
                        Text("\(Yen.format(summary.perDay)) a day for \(summary.daysLeft) days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.top, 4)
            }
            if summary.income != 0 {
                Text("Income \(Yen.format(summary.income, showPlus: true))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Chart

private struct DayValue: Identifiable {
    let day: Int
    let value: Int
    var id: Int { day }
}

/// Running spending this month against last month and the budget. Drag to read any day.
private struct SpendingChart: View {
    let summary: MonthSummary
    @State private var selectedDay: Int?

    private var current: [DayValue] {
        summary.cumulative.enumerated().map { DayValue(day: $0.offset + 1, value: $0.element) }
    }

    private var previous: [DayValue] {
        summary.previous.prefix(summary.daysInMonth).enumerated().map { DayValue(day: $0.offset + 1, value: $0.element) }
    }

    private var shownDay: Int {
        min(max(selectedDay ?? summary.today ?? summary.cumulative.count, 1), summary.daysInMonth)
    }

    private var yMax: Int {
        let top = max(summary.budget, summary.cumulative.last ?? 0, summary.previous.max() ?? 0, 1_000)
        return Int(Double(top) * 1.08)
    }

    private func value(_ series: [Int], at day: Int) -> Int? {
        guard day >= 1 else { return nil }
        if day <= series.count { return series[day - 1] }
        return nil
    }

    private var readoutDate: String {
        if selectedDay == nil, let today = summary.today, today == shownDay { return "Today" }
        let calendar = Calendar.kakeibo
        let date = calendar.date(byAdding: .day, value: shownDay - 1, to: summary.interval.start) ?? summary.interval.start
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(readoutDate).foregroundStyle(.secondary)
                Spacer()
                Text(value(summary.cumulative, at: shownDay).map { Yen.format($0) } ?? "–")
                    .fontWeight(.semibold)
                if let last = value(summary.previous, at: shownDay) {
                    Text("· last month \(Yen.format(last))").foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .monospacedDigit()

            chart
                .frame(height: 180)

            HStack(spacing: 18) {
                LegendSwatch(title: "This month") {
                    Capsule().fill(Color.accentColor).frame(width: 14, height: 3)
                }
                LegendSwatch(title: "Last month") {
                    DashedLine().stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 14, height: 2)
                }
                if summary.budget > 0 {
                    LegendSwatch(title: "Budget") {
                        DashedLine().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 3])).frame(width: 14, height: 1)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spending so far \(Yen.format(summary.spent)) of a \(Yen.format(summary.budget)) budget")
    }

    private var chart: some View {
        Chart {
            ForEach(previous) { point in
                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Spent", point.value),
                    series: .value("Month", "Last month")
                )
                .foregroundStyle(Color.secondary.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            ForEach(current) { point in
                AreaMark(
                    x: .value("Day", point.day),
                    y: .value("Spent", point.value)
                )
                .foregroundStyle(Color.accentColor.opacity(0.12))
            }
            ForEach(current) { point in
                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Spent", point.value),
                    series: .value("Month", "This month")
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if summary.budget > 0 {
                RuleMark(y: .value("Budget", summary.budget))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            RuleMark(x: .value("Day", shownDay))
                .foregroundStyle(Color.primary.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let point = value(summary.cumulative, at: shownDay) {
                PointMark(x: .value("Day", shownDay), y: .value("Spent", point))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(90)
            }
        }
        .chartXScale(domain: 1...summary.daysInMonth)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: [1, 8, 15, 22, summary.daysInMonth]) { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: summary.budget > 0 ? [0, summary.budget] : [0]) { value in
                AxisValueLabel {
                    if let yen = value.as(Int.self) {
                        Text(yen == 0 ? "0" : Yen.short(yen))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDay)
        .sensoryFeedback(.selection, trigger: selectedDay) { _, new in new != nil }
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct LegendSwatch<Swatch: View>: View {
    let title: String
    @ViewBuilder var swatch: Swatch

    var body: some View {
        HStack(spacing: 6) {
            swatch
            Text(title)
        }
    }
}

// MARK: - Quick action

private struct QuickActionLabel: View {
    let title: String
    let symbol: String
    var prominent = false
    var badge = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(prominent ? Color.accentColor : Color.card)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: prominent ? .semibold : .regular))
                            .foregroundStyle(prominent ? Color.white : Color.primary)
                    )
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, badge > 9 ? 4 : 0)
                        .background(Capsule().fill(Color.red))
                        .overlay(Capsule().stroke(Color.groupedBackground, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            Text(title)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge > 0 ? "\(title), \(badge) waiting" : title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Bills

private struct BillsCard: View {
    let reminders: [BillReminder]

    var body: some View {
        if !reminders.isEmpty {
            let shortfalls = shortfallLines
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(reminders.enumerated()), id: \.element.id) { index, reminder in
                        if index > 0 { RowDivider() }
                        row(reminder)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                ForEach(shortfalls, id: \.self) { line in
                    Rectangle().fill(Color.hairline).frame(height: 0.5)
                    Label(line, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.shortfall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.card))
        }
    }

    private var shortfallLines: [String] {
        var worst: [String: Int] = [:]
        var order: [String] = []
        for reminder in reminders where reminder.shortfall > 0 {
            let name = reminder.payFrom?.name ?? "Paying account"
            if worst[name] == nil { order.append(name) }
            worst[name] = max(worst[name] ?? 0, reminder.shortfall)
        }
        return order.map { "\($0) is \(Yen.format(worst[$0] ?? 0)) short for these bills" }
    }

    private func row(_ reminder: BillReminder) -> some View {
        let calendar = Calendar.kakeibo
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                           to: calendar.startOfDay(for: reminder.dueDate)).day ?? 0
        let urgent = reminder.isOverdue || days <= 3
        let when: String
        if reminder.isOverdue {
            when = "Was due \(reminder.dueDate.formatted(.dateTime.day().month(.abbreviated)))"
        } else if days == 0 {
            when = "Due today"
        } else {
            when = "Due \(reminder.dueDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
                + (days <= 3 ? " · in \(days) day\(days == 1 ? "" : "s")" : "")
        }
        return HStack(spacing: 12) {
            IconTile(symbol: "calendar", tint: reminder.isOverdue ? .red : .orange, neutral: !urgent)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.account.name).font(.body.weight(.semibold))
                Text(when)
                    .font(.footnote)
                    .foregroundStyle(reminder.isOverdue ? Color.shortfall : Color.secondary)
            }
            Spacer()
            Text(Yen.format(reminder.due)).font(.body.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Budgets preview

/// The three categories most worth a look: over budget first, then the fullest.
private struct BudgetsPreview: View {
    let categories: [BudgetCategory]
    let summary: MonthSummary
    let seeAll: () -> Void

    var body: some View {
        let picked = pick()
        if !picked.isEmpty {
            VStack(spacing: 10) {
                SectionHeader(title: "Budgets") {
                    Button("See all", action: seeAll)
                }
                RowsCard {
                    ForEach(Array(picked.enumerated()), id: \.element.id) { index, category in
                        if index > 0 { RowDivider() }
                        CategoryBudgetRow(category: category, spent: summary.spending[category.id] ?? 0)
                            .padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private func pick() -> [BudgetCategory] {
        let candidates = categories.filter { category in
            guard category.kind == .expense, !category.isArchived, category.monthlyBudget > 0 else { return false }
            // A fixed cost paid exactly (rent) needs no attention.
            return (summary.spending[category.id] ?? 0) != category.monthlyBudget
        }
        func fraction(_ category: BudgetCategory) -> Double {
            Double(summary.spending[category.id] ?? 0) / Double(category.monthlyBudget)
        }
        return Array(candidates.sorted { fraction($0) > fraction($1) }.prefix(3))
    }
}

/// Icon, name, what's left, a thin bar and "¥x of ¥y".
struct CategoryBudgetRow: View {
    let category: BudgetCategory
    let spent: Int
    var compact = false

    var body: some View {
        let budget = category.isArchived ? 0 : category.monthlyBudget
        let over = budget > 0 && spent > budget
        let look = CategoryLook.of(category)
        HStack(spacing: 12) {
            CategoryTile(category: category, size: compact ? 36 : 40)
            VStack(alignment: .leading, spacing: compact ? 7 : 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(category.name).font(compact ? .callout : .body)
                    Spacer()
                    Text(note(budget: budget, over: over))
                        .font(compact ? .footnote : .subheadline)
                        .fontWeight(over ? .semibold : .regular)
                        .foregroundStyle(over ? Color.shortfall : Color.secondary)
                        .monospacedDigit()
                }
                if budget > 0 {
                    ProgressBar(fraction: Double(spent) / Double(budget), isOver: over,
                                tint: look.tint, height: compact ? 5 : 6)
                }
                if !compact && budget > 0 {
                    Text("\(Yen.format(spent)) of \(Yen.format(budget))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func note(budget: Int, over: Bool) -> String {
        guard budget > 0 else { return Yen.format(spent) }
        if over { return "\(Yen.format(spent - budget)) over" }
        if !compact { return "\(Yen.format(budget - spent)) left" }
        if spent == budget { return "Paid · \(Yen.format(spent))" }
        if spent == 0 { return "Nothing yet · \(Yen.format(budget))" }
        return "\(Yen.format(spent)) of \(Yen.format(budget))"
    }
}

// MARK: - Edit Home

struct EditHomeView: View {
    @Binding var order: String
    @Binding var hidden: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sections = HomeSection.order(from: order)
        let hiddenSet = HomeSection.hidden(from: hidden)
        NavigationStack {
            List {
                Section {
                    ForEach(sections) { section in
                        Toggle(isOn: Binding(
                            get: { !hiddenSet.contains(section) },
                            set: { shown in
                                var updated = hiddenSet
                                if shown { updated.remove(section) } else { updated.insert(section) }
                                hidden = HomeSection.encode(HomeSection.allCases.filter { updated.contains($0) })
                                Haptics.selection()
                            }
                        )) {
                            Label(section.title, systemImage: section.symbol)
                        }
                    }
                    .onMove { from, to in
                        var updated = sections
                        updated.move(fromOffsets: from, toOffset: to)
                        order = HomeSection.encode(updated)
                        Haptics.lift()
                    }
                } footer: {
                    Text("Drag to change the order. Turn a section off to hide it. The spending graph and quick actions always stay at the top.")
                }
                Section {
                    Button("Reset to default") {
                        order = HomeSection.defaultOrder
                        hidden = ""
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Review list

/// Unconfirmed payoffs and entries logged from Shortcuts.
struct ReviewListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @State private var editing: Entry?

    var body: some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        let payoffs = entries.filter { $0.kind == .payoff && !$0.isConfirmed }
        let review = entries.filter { $0.needsReview }
        List {
            if !payoffs.isEmpty {
                Section {
                    ForEach(payoffs) { entry in
                        HStack {
                            Button { editing = entry } label: { EntryRow(entry: entry, lookup: lookup) }
                                .buttonStyle(.plain)
                            Button {
                                entry.isConfirmed = true
                                context.saveAndRefresh()
                                Haptics.success()
                            } label: {
                                Image(systemName: "checkmark.circle").font(.title2)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Confirm payoff")
                        }
                    }
                } header: {
                    Text("Payoffs to confirm")
                } footer: {
                    Text("Tick once you've seen the debit in your bank. Tap to fix the amount.")
                }
            }
            if !review.isEmpty {
                Section("Logged automatically") {
                    ForEach(review) { entry in
                        Button { editing = entry } label: { EntryRow(entry: entry, lookup: lookup) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Looks right") {
                                    entry.needsReview = false
                                    context.saveAndRefresh()
                                    Haptics.success()
                                }
                                .tint(.green)
                            }
                    }
                }
            }
            if payoffs.isEmpty && review.isEmpty {
                Text("Nothing to review.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("To review")
        .sheet(item: $editing) { entry in
            EntryEditorRouter(entry: entry)
        }
    }
}
