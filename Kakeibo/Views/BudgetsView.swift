import Charts
import SwiftData
import SwiftUI

/// The Budgets tab: This Month (Budgets artboard) and Trends (Trends artboard).
struct BudgetsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case month, trends
        var id: String { rawValue }
    }

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @State private var page: Page = DemoMode.screen == "trends" ? .trends : .month
    @State private var monthOffset = 0

    var body: some View {
        let now = Date()
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("View", selection: $page) {
                        Text("This Month").tag(Page.month)
                        Text("Trends").tag(Page.trends)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                    switch page {
                    case .month:
                        let month = Calendar.kakeibo.date(byAdding: .month, value: monthOffset, to: now) ?? now
                        ThisMonthBudgets(pace: BudgetPace(ledger: ledger, month: month, now: now), monthOffset: $monthOffset)
                    case .trends:
                        TrendsView(trends: SpendingTrends(ledger: ledger, now: now), now: now)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
            }
            .kScreenBackground()
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit") {
                        CategoriesView()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AddEntryButton()
                }
            }
            .sensoryFeedback(.firmSelection, trigger: page)
        }
    }
}

// MARK: - This Month

struct ThisMonthBudgets: View {
    let pace: BudgetPace
    @Binding var monthOffset: Int

    var body: some View {
        overview
            .padding(.top, 16)
        if !pace.needsAttention.isEmpty {
            SectionTitle("Needs attention")
                .padding(.top, Metrics.sectionSpacing)
            categoryList(pace.needsAttention)
                .padding(.top, 10)
        }
        if !pace.onTrack.isEmpty {
            SectionTitle("On track")
                .padding(.top, Metrics.sectionSpacing)
            categoryList(pace.onTrack)
                .padding(.top, 10)
        }
        if !pace.unbudgeted.isEmpty {
            SectionTitle(pace.needsAttention.isEmpty && pace.onTrack.isEmpty ? "Spending" : "No budget set")
                .padding(.top, Metrics.sectionSpacing)
            CardList {
                ForEach(Array(pace.unbudgeted.enumerated()), id: \.element.category.id) { index, item in
                    if index > 0 { ListDivider(inset: 56) }
                    NavigationLink {
                        CategoryDetailView(category: item.category, month: pace.interval.start)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: item.category, size: 28)
                            Text(item.category.name)
                                .foregroundStyle(Palette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Yen.format(item.spent))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: Metrics.compactRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
            Text(pace.budget > 0
                 ? "Not counted in your budget. Still in trends and balances."
                 : "Still counted in spending and trends. Tap Edit to give any category a budget.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    private var monthTitle: String {
        pace.interval.start.formatted(.dateTime.month(.wide).year())
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    monthButton("chevron.left", label: "Previous month", enabled: true) { monthOffset -= 1 }
                    monthButton("chevron.right", label: "Next month", enabled: monthOffset < 0) { monthOffset += 1 }
                }
            }
            .frame(height: 30)
            if pace.budget > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Yen.format(abs(pace.left)))
                        .font(.kDetailAmount)
                        .tracking(-1)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(pace.left < 0 ? Palette.negativeText : Palette.textPrimary)
                    Text("\(pace.left < 0 ? "over" : "left of") \(Yen.format(pace.budget))")
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
                .padding(.top, 10)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Yen.format(pace.spent))
                        .font(.kDetailAmount)
                        .tracking(-1)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text("spent").foregroundStyle(Palette.textSecondary)
                }
                .padding(.top, 10)
            }
            SplitBar(pace: pace)
                .padding(.top, 14)
            HStack(alignment: .top, spacing: 10) {
                stat("Spent", Yen.format(pace.spent))
                if pace.isCurrentMonth && pace.budget > 0 {
                    stat(pace.daysRemaining == 1 ? "1 day left" : "\(pace.daysRemaining) days left",
                         pace.perDay > 0 ? "\(Yen.format(pace.perDay))/day" : "–")
                } else {
                    stat("Budget", pace.budget > 0 ? Yen.format(pace.budget) : "–")
                }
                stat("vs \(pace.comparisonLabel())", pace.previousSameDays > 0 ? Yen.format(pace.vsPrevious, showPlus: true) : "–",
                     color: pace.previousSameDays == 0 ? Palette.textPrimary : (pace.vsPrevious <= 0 ? Palette.positive : Palette.warning))
            }
            .padding(.top, 12)
            if pace.outsideBudgets > 0 {
                OutsideBudgetsLine(amount: pace.outsideBudgets)
                    .padding(.top, 6)
            }
            if pace.budget > 0 && pace.isCurrentMonth {
                statusChip
                    .padding(.top, 14)
            }
        }
        .kCard(padding: 18)
    }

    @ViewBuilder
    private var statusChip: some View {
        let gap = abs(pace.pace - pace.spent)
        switch pace.status {
        case .onTrack:
            StatusChip(text: "On track · \(Yen.format(gap)) under today's pace", tint: Palette.positive, dot: true)
        case .atRisk:
            StatusChip(text: "Ahead of pace · \(Yen.format(gap)) over today's pace", tint: Palette.warning, dot: true)
        case .over:
            StatusChip(text: "Over budget by \(Yen.format(-pace.left))", tint: Palette.negativeText, dot: true)
        }
    }

    private func monthButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Palette.textPrimary : Palette.textTertiary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(enabled ? Palette.controlFill : Palette.controlFill.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func stat(_ title: String, _ value: String, color: Color = Palette.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryList(_ items: [CategoryPace]) -> some View {
        CardList {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { ListDivider() }
                NavigationLink {
                    CategoryDetailView(category: item.category, month: pace.interval.start)
                } label: {
                    BudgetCategoryRow(item: item, showsPace: pace.isCurrentMonth, monthStart: pace.interval.start,
                                      comparison: pace.comparisonLabel())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// "+ ¥85,000 outside budgets": spending in categories without a budget, left out of the budget totals.
struct OutsideBudgetsLine: View {
    let amount: Int

    var body: some View {
        Text("+ \(Yen.format(amount)) outside budgets")
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// This month's spending split by category on one bar, scaled to the whole budget, with today's pace.
struct SplitBar: View {
    let pace: BudgetPace

    private struct Segment: Identifiable {
        let id: UUID
        let value: Int
        let color: Color
    }

    var body: some View {
        // With budgets set, only budgeted categories fill the bar; without any, everything does.
        let budgetedSegments = (pace.needsAttention + pace.onTrack).map { Segment(id: $0.id, value: $0.spent, color: CategoryLook.of($0.category).tint) }
        let looseSegments: [Segment] = pace.budget > 0 ? []
            : pace.unbudgeted.map { Segment(id: $0.category.id, value: $0.spent, color: CategoryLook.of($0.category).tint) }
        let segments = budgetedSegments + looseSegments
        let shown = segments.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let scale = Double(max(pace.budget, pace.spent, 1))
        let tick: Double? = pace.isCurrentMonth && pace.budget > 0 ? pace.paceFraction : nil
        VStack(spacing: 0) {
            GeometryReader { geo in
                let gaps = CGFloat(max(shown.count - 1, 0)) * 2
                let width = max(geo.size.width - gaps, 0)
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(shown) { segment in
                            Rectangle()
                                .fill(segment.color)
                                .frame(width: width * CGFloat(Double(segment.value) / scale))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 14)
                    .background(Palette.track)
                    .clipShape(Capsule())
                    if let tick {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Palette.paceTick)
                            .frame(width: 2, height: 20)
                            .offset(x: geo.size.width * tick - 1)
                    }
                }
                .frame(width: geo.size.width, height: 14)
            }
            .frame(height: 14)
            if let tick {
                GeometryReader { geo in
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize()
                        .position(x: min(max(geo.size.width * tick, 16), max(geo.size.width - 16, 16)), y: geo.size.height / 2)
                }
                .frame(height: 13)
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spent by category: " + shown.compactMap { segment in
            (pace.needsAttention + pace.onTrack).first { $0.id == segment.id }.map { "\($0.category.name) \(Yen.format($0.spent))" }
        }.joined(separator: ", "))
    }
}

/// A budgeted category: what's left (or over), a bar with today's pace and one line of context.
struct BudgetCategoryRow: View {
    let item: CategoryPace
    var showsPace = true
    let monthStart: Date
    var comparison: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: item.category)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.category.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 8)
                    Text(trailing)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(trailingColor)
                }
                BudgetBar(fraction: item.fraction, pace: showsPace ? item.paceFraction : nil,
                          tint: item.status == .atRisk ? Palette.warning : CategoryLook.of(item.category).tint, height: 6)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var trailing: String {
        item.status == .over ? "\(Yen.format(item.spent - item.budget)) over" : "\(Yen.format(item.left)) left"
    }

    private var trailingColor: Color {
        switch item.status {
        case .over: return Palette.negativeText
        case .atRisk: return Palette.warning
        case .onTrack: return Palette.textPrimary
        }
    }

    private var caption: String {
        let base = "\(Yen.format(item.spent)) of \(Yen.format(item.budget))"
        switch item.status {
        case .over:
            guard item.previousSameDays > 0, !comparison.isEmpty else { return base }
            let delta = item.vsPrevious
            return delta >= 0 ? "\(base) · \(Yen.format(delta)) more than \(comparison)" : "\(base) · \(Yen.format(-delta)) less than \(comparison)"
        case .atRisk:
            if let day = item.runsOutDay, let date = Calendar.kakeibo.date(byAdding: .day, value: day - 1, to: monthStart) {
                return "At this pace it runs out around \(date.formatted(.dateTime.month(.abbreviated).day()))"
            }
            return "\(base) · ahead of today's pace"
        case .onTrack:
            return base
        }
    }
}

// MARK: - Trends

struct TrendsView: View {
    let trends: SpendingTrends
    let now: Date

    var body: some View {
        spendingSoFar
            .padding(.top, 16)
        monthly
            .padding(.top, 16)
        if !trends.categoryChanges.isEmpty {
            categoryChanges
                .padding(.top, 16)
        }
        if trends.lastMonthIncome > 0 {
            kept
                .padding(.top, 16)
        }
    }

    private var monthName: String { now.formatted(.dateTime.month(.wide)) }
    private var previousName: String { trends.lastMonthStart.formatted(.dateTime.month(.wide)) }

    private struct DayPoint: Identifiable {
        let day: Int
        let value: Int
        let series: String
        var id: String { "\(series)-\(day)" }
    }

    private var spendingSoFar: some View {
        let today = trends.current.count
        let comparisonEnd = min(today, trends.previous.count)
        let previousSoFar = comparisonEnd > 0 ? trends.previous[comparisonEnd - 1] : 0
        let spent = trends.current.last ?? 0
        let monthShort = now.formatted(.dateTime.month(.abbreviated))
        let previousShort = trends.lastMonthStart.formatted(.dateTime.month(.abbreviated))
        let points = trends.current.enumerated().map { DayPoint(day: $0.offset + 1, value: $0.element, series: monthName) }
            + trends.previous.enumerated().map { DayPoint(day: $0.offset + 1, value: $0.element, series: previousName) }
            + trends.average.prefix(trends.daysInMonth).enumerated().map { DayPoint(day: $0.offset + 1, value: $0.element, series: "Average") }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spending so far").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("\(monthShort) 1–\(today) · all categories").font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            Text(Yen.format(spent))
                .font(.kStat)
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
            if previousSoFar > 0 {
                ComparisonLine(delta: spent - previousSoFar, label: "\(previousShort) 1–\(comparisonEnd)")
            }
            Chart(points) { point in
                LineMark(x: .value("Day", point.day), y: .value("Spent", point.value), series: .value("Month", point.series))
                    .foregroundStyle(color(point.series))
                    .lineStyle(point.series == "Average"
                               ? StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                               : StrokeStyle(lineWidth: point.series == monthName ? 2.5 : 2, lineCap: .round, lineJoin: .round))
            }
            .chartXScale(domain: 1...max(trends.daysInMonth, 2))
            .chartXAxis {
                AxisMarks(values: [1, 8, 15, 22, 29]) { _ in AxisValueLabel() }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(Palette.separator)
                    AxisValueLabel { if let yen = value.as(Int.self) { Text(yen == 0 ? "¥0" : Yen.short(yen)) } }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 170)
            .padding(.top, 12)
            HStack(spacing: 14) {
                legend(monthName, color: color(monthName))
                legend(previousName, color: color(previousName))
                if trends.averageMonths > 0 {
                    HStack(spacing: 6) {
                        Capsule().stroke(Palette.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 16, height: 2)
                        Text("\(trends.averageMonths)-month average")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, 10)
        }
        .kCard()
    }

    private func color(_ series: String) -> Color {
        if series == monthName { return Palette.accentData }
        if series == "Average" { return Palette.textSecondary }
        return Hue.gray.color
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 16, height: 3)
            Text(title)
        }
    }

    private var monthly: some View {
        let label: (MonthTotal) -> String = { $0.start.formatted(.dateTime.month(.abbreviated)) }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Monthly spending").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            Text(monthlySubtitle)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
            Chart {
                ForEach(trends.months) { total in
                    if total.isCurrent && trends.projected > total.spent {
                        BarMark(x: .value("Month", label(total)), y: .value("Spent", trends.projected), width: .fixed(28))
                            .foregroundStyle(Palette.accentData.opacity(0.25))
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                Text("~" + String(Yen.short(trends.projected).dropFirst()))
                                    .font(.caption2)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                    }
                    BarMark(x: .value("Month", label(total)), y: .value("Spent", total.spent), width: .fixed(28))
                        .foregroundStyle(total.isCurrent ? Palette.accentData : Hue.gray.color.opacity(0.6))
                        .cornerRadius(6)
                        .annotation(position: total.isCurrent && trends.projected > total.spent ? .overlay : .top) {
                            Text(Yen.short(total.spent).dropFirst())
                                .font(.caption2)
                                .foregroundStyle(total.isCurrent ? Palette.textPrimary : Palette.textSecondary)
                        }
                }
                if trends.averageMonthly > 0 {
                    RuleMark(y: .value("Average", trends.averageMonthly))
                        .foregroundStyle(Palette.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 170)
            .padding(.top, 12)
        }
        .kCard()
    }

    private var monthlySubtitle: String {
        var parts: [String] = []
        if trends.averageMonthly > 0 { parts.append("Average \(Yen.format(trends.averageMonthly))") }
        parts.append("\(monthName) on pace for about \(Yen.format(trends.projected / 1_000 * 1_000))")
        return parts.joined(separator: " · ")
    }

    private var categoryChanges: some View {
        let biggest = Double(max(trends.categoryChanges.map { abs($0.vsPrevious) }.max() ?? 1, 1))
        let previousShort = trends.lastMonthStart.formatted(.dateTime.month(.abbreviated))
        return VStack(alignment: .leading, spacing: 0) {
            Text("By category, vs \(previousShort) 1–\(trends.current.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Same days, budgeted categories")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
            VStack(spacing: 0) {
                ForEach(trends.categoryChanges) { item in
                    let less = item.vsPrevious < 0
                    HStack(spacing: 8) {
                        Text(item.category.name)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .frame(width: 128, alignment: .leading)
                        GeometryReader { geo in
                            let half = geo.size.width / 2
                            let length = max(half * CGFloat(Double(abs(item.vsPrevious)) / biggest), 3)
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Palette.textSecondary.opacity(0.45))
                                    .frame(width: 1, height: 34)
                                    .offset(x: half)
                                UnevenRoundedRectangle(
                                    topLeadingRadius: less ? 6 : 0, bottomLeadingRadius: less ? 6 : 0,
                                    bottomTrailingRadius: less ? 0 : 6, topTrailingRadius: less ? 0 : 6, style: .continuous)
                                    .fill(less ? Palette.info : Palette.warning)
                                    .frame(width: length, height: 12)
                                    .offset(x: less ? half - length : half)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        Text(Yen.format(item.vsPrevious, showPlus: true))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(less ? Palette.info : Palette.warning)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .frame(height: 34)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 12)
            HStack(spacing: 16) {
                HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(Palette.info).frame(width: 10, height: 10); Text("Spent less") }
                HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(Palette.warning).frame(width: 10, height: 10); Text("Spent more") }
            }
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, 12)
        }
        .kCard()
    }

    private var kept: some View {
        let share = trends.lastMonthIncome > 0 ? Int((Double(trends.kept) / Double(trends.lastMonthIncome) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 0) {
            Text("Kept in \(previousName)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            Text(Yen.format(trends.kept))
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(trends.kept >= 0 ? Palette.positive : Palette.negativeText)
            Text("\(share)% of income · \(Yen.format(trends.lastMonthIncome)) in, \(Yen.format(trends.lastMonthSpent)) spent")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .kCard()
    }
}
