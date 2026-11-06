import Foundation

extension Ledger {
    /// Running total of my spending for each day of `interval`, stopping at `end` (exclusive) if given.
    /// Index 0 is the first day.
    func cumulativeSpending(in interval: DateInterval, until end: Date? = nil, categoryID: UUID? = nil,
                            calendar: Calendar = .kakeibo) -> [Int] {
        let limit = min(end ?? interval.end, interval.end)
        var totals: [Int] = []
        var running = 0
        var dayStart = interval.start
        while dayStart < limit {
            let next = min(calendar.date(byAdding: .day, value: 1, to: dayStart) ?? interval.end, interval.end)
            guard next > dayStart else { break }
            let day = DateInterval(start: dayStart, end: next)
            running += categoryID.map { spendingByCategory(in: day)[$0] ?? 0 } ?? totalSpending(in: day)
            totals.append(running)
            dayStart = next
        }
        return totals
    }

    /// Total monthly budget across active expense categories.
    var totalBudget: Int {
        categories.filter { $0.kind == .expense && !$0.isArchived }.reduce(0) { $0 + $1.monthlyBudget }
    }
}

/// Everything Home and Budgets show for one month.
struct MonthSummary {
    let interval: DateInterval
    let spent: Int
    let budget: Int
    let income: Int
    let spending: [UUID: Int]
    let daysInMonth: Int
    /// Day of the month for the current month, nil for past months.
    let today: Int?
    /// Running total by day, up to today for the current month.
    let cumulative: [Int]
    /// Running total by day for the month before.
    let previous: [Int]

    init(ledger: Ledger, month: Date, now: Date = Date(), calendar: Calendar = .kakeibo) {
        let interval = Ledger.monthInterval(containing: month, calendar: calendar)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: interval.start) ?? interval.start
        let previousInterval = Ledger.monthInterval(containing: previousStart, calendar: calendar)
        let isCurrent = interval.contains(now)

        self.interval = interval
        spending = ledger.spendingByCategory(in: interval)
        spent = spending.values.reduce(0, +)
        budget = ledger.totalBudget
        income = ledger.incomeByCategory(in: interval).values.reduce(0, +)
        daysInMonth = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
        today = isCurrent ? calendar.component(.day, from: now) : nil
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        cumulative = ledger.cumulativeSpending(in: interval, until: isCurrent ? endOfToday : nil, calendar: calendar)
        previous = ledger.cumulativeSpending(in: previousInterval, calendar: calendar)
    }

    var left: Int { budget - spent }

    /// Days after today. Zero on the last day and for past months.
    var daysLeft: Int {
        guard let today else { return 0 }
        return max(daysInMonth - today, 0)
    }

    /// What can be spent per day for the rest of the month and stay on budget.
    var perDay: Int {
        guard budget > 0, left > 0, today != nil else { return 0 }
        return left / max(daysLeft, 1)
    }
}

/// Totals for the last few months, oldest first.
struct MonthTotal: Identifiable {
    let start: Date
    let spent: Int
    let isCurrent: Bool
    var id: Date { start }
}

extension Ledger {
    /// Spending per month for the last `count` months (this one included), optionally one category only.
    func monthTotals(count: Int, now: Date = Date(), categoryID: UUID? = nil, calendar: Calendar = .kakeibo) -> [MonthTotal] {
        let thisMonth = Ledger.monthInterval(containing: now, calendar: calendar).start
        return (0..<count).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { return nil }
            let interval = Ledger.monthInterval(containing: start, calendar: calendar)
            let spent = categoryID.map { spendingByCategory(in: interval)[$0] ?? 0 } ?? totalSpending(in: interval)
            return MonthTotal(start: start, spent: spent, isCurrent: back == 0)
        }
    }

    func totalIncome(in interval: DateInterval) -> Int {
        incomeByCategory(in: interval).values.reduce(0, +)
    }
}

/// The Trends view: this month's running total against last month and the recent average, monthly
/// totals with a projection, category changes over the same days, and what was kept last month.
struct SpendingTrends {
    /// Running total by day this month, up to today.
    let current: [Int]
    /// Running total by day for all of last month.
    let previous: [Int]
    /// Average running total by day over the last five months that had any spending (31 values).
    let average: [Int]
    let averageMonths: Int
    /// The last six months, this one last.
    let months: [MonthTotal]
    /// Average monthly spending over the months before this one that had any.
    let averageMonthly: Int
    /// This month at its daily rate so far.
    let projected: Int
    let daysInMonth: Int
    /// Budgeted categories against the same days last month, biggest drop first.
    let categoryChanges: [CategoryPace]
    /// Last month's income, spending and what was kept.
    let lastMonthStart: Date
    let lastMonthIncome: Int
    let lastMonthSpent: Int

    init(ledger: Ledger, now: Date = Date(), calendar: Calendar = .kakeibo) {
        let summary = MonthSummary(ledger: ledger, month: now, now: now, calendar: calendar)
        let pace = BudgetPace(ledger: ledger, month: now, now: now, calendar: calendar)
        let thisMonth = summary.interval.start

        var curves: [[Int]] = []
        for back in 1...5 {
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { continue }
            let curve = ledger.cumulativeSpending(in: Ledger.monthInterval(containing: start, calendar: calendar), calendar: calendar)
            guard let last = curve.last, last > 0 else { continue }
            curves.append(curve + Array(repeating: last, count: max(31 - curve.count, 0)))
        }
        average = curves.isEmpty ? [] : (0..<31).map { day in curves.reduce(0) { $0 + $1[day] } / curves.count }
        averageMonths = curves.count

        let totals = ledger.monthTotals(count: 6, now: now, calendar: calendar)
        let past = totals.filter { !$0.isCurrent && $0.spent > 0 }
        current = summary.cumulative
        previous = summary.previous
        months = totals
        averageMonthly = past.isEmpty ? 0 : past.reduce(0) { $0 + $1.spent } / past.count
        projected = pace.projected
        daysInMonth = summary.daysInMonth
        categoryChanges = (pace.needsAttention + pace.onTrack)
            .filter { $0.vsPrevious != 0 }
            .sorted { $0.vsPrevious < $1.vsPrevious }

        let lastStart = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let lastInterval = Ledger.monthInterval(containing: lastStart, calendar: calendar)
        lastMonthStart = lastStart
        lastMonthIncome = ledger.totalIncome(in: lastInterval)
        lastMonthSpent = ledger.totalSpending(in: lastInterval)
    }

    var kept: Int { lastMonthIncome - lastMonthSpent }
}

extension Ledger {
    /// True when my spending in this category, for the month containing `date`, is above its monthly budget.
    /// Categories without a budget, archived ones and income categories are never over.
    func isOverBudget(categoryID: UUID?, inMonthOf date: Date, calendar: Calendar = .kakeibo) -> Bool {
        guard let categoryID,
              let category = categories.first(where: { $0.id == categoryID }),
              category.kind == .expense, !category.isArchived, category.monthlyBudget > 0 else { return false }
        let interval = Ledger.monthInterval(containing: date, calendar: calendar)
        return (spendingByCategory(in: interval)[categoryID] ?? 0) > category.monthlyBudget
    }
}

/// How the Budgets tab splits categories: the ones with a budget are always listed, the rest
/// sit behind "See all categories".
struct BudgetListing {
    /// Active expense categories with a monthly budget, in their usual order.
    let budgeted: [BudgetCategory]
    /// Active expense categories without a budget, plus archived ones that have spending this month.
    let unbudgeted: [BudgetCategory]
    /// My spending this month in `unbudgeted`.
    let unbudgetedSpent: Int

    init(categories: [BudgetCategory], spending: [UUID: Int]) {
        let expenses = categories.filter { $0.kind == .expense }
        budgeted = expenses.filter { !$0.isArchived && $0.monthlyBudget > 0 }
        unbudgeted = expenses.filter { category in
            category.isArchived ? (spending[category.id] ?? 0) != 0 : category.monthlyBudget <= 0
        }
        unbudgetedSpent = unbudgeted.reduce(0) { $0 + (spending[$1.id] ?? 0) }
    }

    /// With no budgets set at all, hiding everything would leave an empty list, so show it all.
    var showsEverything: Bool { budgeted.isEmpty }
}

// MARK: - Pace

/// How a budget is doing against the calendar.
enum PaceStatus: Equatable {
    /// Spent more than the budget.
    case over
    /// Ahead of today's pace: at this month's daily rate it runs out before the month ends.
    case atRisk
    /// At or under today's pace (or exactly used up, like rent).
    case onTrack
}

/// One budgeted category this month.
struct CategoryPace: Identifiable {
    let category: BudgetCategory
    let spent: Int
    let budget: Int
    /// Where spending would be if it were spread evenly: budget × days elapsed ÷ days in the month.
    let pace: Int
    /// Month-end total at this month's daily rate.
    let projected: Int
    /// Day of the month the budget runs out at this rate, when that's before the month ends.
    let runsOutDay: Int?
    /// Spent in the same days of the month before (Oct 1–18 when today is Nov 18).
    let previousSameDays: Int
    let status: PaceStatus

    var id: UUID { category.id }
    var left: Int { budget - spent }
    var fraction: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
    var paceFraction: Double { budget > 0 ? Double(pace) / Double(budget) : 0 }
    var vsPrevious: Int { spent - previousSameDays }
}

/// The Budgets tab and the Summary budget card for one month: totals, today's pace, like-for-like
/// comparison with the month before, and categories sorted by how much attention they need.
struct BudgetPace {
    let interval: DateInterval
    let daysInMonth: Int
    /// Days counted so far, today included. All of them for a past month.
    let daysElapsed: Int
    let isCurrentMonth: Bool
    let budget: Int
    let spent: Int
    /// budget × days elapsed ÷ days in the month.
    let pace: Int
    /// Spending in the month before over the same days.
    let previousSameDays: Int
    /// Last day of the month before that the comparison covers (Oct 18 for Nov 18).
    let previousComparisonEnd: Date
    let previousStart: Date
    /// Budgeted categories: over budget (biggest overspend first), then at risk (soonest to run out).
    let needsAttention: [CategoryPace]
    /// The rest of the budgeted categories, fullest first.
    let onTrack: [CategoryPace]
    /// Categories with spending but no budget, biggest first. Still counted in `spent`.
    let unbudgeted: [(category: BudgetCategory, spent: Int)]

    init(ledger: Ledger, month: Date, now: Date = Date(), calendar: Calendar = .kakeibo) {
        let interval = Ledger.monthInterval(containing: month, calendar: calendar)
        let days = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
        let current = interval.contains(now)
        let elapsed = current ? calendar.component(.day, from: now) : days

        let previousStart = calendar.date(byAdding: .month, value: -1, to: interval.start) ?? interval.start
        let previousInterval = Ledger.monthInterval(containing: previousStart, calendar: calendar)
        let previousDays = calendar.range(of: .day, in: .month, for: previousStart)?.count ?? 30
        let sameDays = current ? min(elapsed, previousDays) : previousDays
        let previousEnd = calendar.date(byAdding: .day, value: sameDays, to: previousStart) ?? previousInterval.end
        let previousSpending = ledger.spendingByCategory(in: DateInterval(start: previousStart, end: previousEnd))

        let spending = ledger.spendingByCategory(in: interval)
        let budgeted = ledger.categories.filter { $0.kind == .expense && !$0.isArchived && $0.monthlyBudget > 0 }

        var paces: [CategoryPace] = []
        for category in budgeted {
            let spent = spending[category.id] ?? 0
            paces.append(BudgetPace.categoryPace(category, spent: spent, elapsed: elapsed, days: days,
                                                 previous: previousSpending[category.id] ?? 0))
        }
        let over = paces.filter { $0.status == .over }.sorted { $0.spent - $0.budget > $1.spent - $1.budget }
        let atRisk = paces.filter { $0.status == .atRisk }
            .sorted { ($0.runsOutDay ?? Int.max, -$0.fraction) < ($1.runsOutDay ?? Int.max, -$1.fraction) }
        let fine = paces.filter { $0.status == .onTrack }.sorted { $0.fraction > $1.fraction }

        let budgetedIDs = Set(budgeted.map(\.id))
        var loose: [(category: BudgetCategory, spent: Int)] = []
        for category in ledger.categories where category.kind == .expense && !budgetedIDs.contains(category.id) {
            let spent = spending[category.id] ?? 0
            if spent != 0 { loose.append((category: category, spent: spent)) }
        }
        loose.sort { $0.spent > $1.spent }

        let totalBudget = ledger.totalBudget
        self.interval = interval
        daysInMonth = days
        daysElapsed = elapsed
        isCurrentMonth = current
        budget = totalBudget
        spent = spending.values.reduce(0, +)
        pace = totalBudget * elapsed / max(days, 1)
        previousSameDays = previousSpending.values.reduce(0, +)
        previousComparisonEnd = calendar.date(byAdding: .day, value: -1, to: previousEnd) ?? previousEnd
        self.previousStart = previousStart
        needsAttention = over + atRisk
        onTrack = fine
        unbudgeted = loose
    }

    static func categoryPace(_ category: BudgetCategory, spent: Int, elapsed: Int, days: Int, previous: Int) -> CategoryPace {
        let budget = category.monthlyBudget
        let pace = budget * elapsed / max(days, 1)
        let projected = elapsed > 0 ? spent * days / elapsed : spent
        var runsOut: Int?
        if spent > 0, spent < budget, projected > budget {
            let day = Int((Double(budget) * Double(elapsed) / Double(spent)).rounded(.up))
            if day <= days { runsOut = day }
        }
        let status: PaceStatus
        if spent > budget {
            status = .over
        } else if spent < budget && spent > pace {
            status = .atRisk
        } else {
            status = .onTrack
        }
        return CategoryPace(category: category, spent: spent, budget: budget, pace: pace, projected: projected,
                            runsOutDay: runsOut, previousSameDays: previous, status: status)
    }

    var left: Int { budget - spent }
    var fraction: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
    var paceFraction: Double { daysInMonth > 0 ? Double(daysElapsed) / Double(daysInMonth) : 0 }

    var status: PaceStatus {
        if budget > 0 && spent > budget { return .over }
        if spent > pace { return .atRisk }
        return .onTrack
    }

    /// Spent minus the same days of the month before. Negative means spending less.
    var vsPrevious: Int { spent - previousSameDays }

    /// Days after today. Zero on the last day and for past months.
    var daysRemaining: Int { isCurrentMonth ? max(daysInMonth - daysElapsed, 0) : 0 }

    /// What can be spent per day for the rest of the month and stay on budget (today's if it's the last day).
    var perDay: Int {
        guard budget > 0, left > 0, isCurrentMonth else { return 0 }
        return left / max(daysRemaining, 1)
    }

    /// Month-end total at this month's daily rate.
    var projected: Int { daysElapsed > 0 ? spent * daysInMonth / daysElapsed : spent }

    /// "Oct 1–18" (or "October" for a whole month).
    func comparisonLabel(calendar: Calendar = .kakeibo) -> String {
        if !isCurrentMonth {
            return previousStart.formatted(.dateTime.month(.wide))
        }
        let month = previousStart.formatted(.dateTime.month(.abbreviated))
        let last = calendar.component(.day, from: previousComparisonEnd)
        return last == 1 ? "\(month) 1" : "\(month) 1–\(last)"
    }
}
