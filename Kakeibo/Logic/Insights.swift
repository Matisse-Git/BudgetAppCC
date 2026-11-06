import Foundation

extension Ledger {
    /// Running total of my spending for each day of `interval`, stopping at `end` (exclusive) if given.
    /// Index 0 is the first day.
    func cumulativeSpending(in interval: DateInterval, until end: Date? = nil, calendar: Calendar = .kakeibo) -> [Int] {
        let limit = min(end ?? interval.end, interval.end)
        var totals: [Int] = []
        var running = 0
        var dayStart = interval.start
        while dayStart < limit {
            let next = min(calendar.date(byAdding: .day, value: 1, to: dayStart) ?? interval.end, interval.end)
            guard next > dayStart else { break }
            running += totalSpending(in: DateInterval(start: dayStart, end: next))
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

    /// Days left including today. Zero for past months.
    var daysLeft: Int {
        guard let today else { return 0 }
        return max(daysInMonth - today + 1, 0)
    }

    /// What can be spent per day for the rest of the month and stay on budget.
    var perDay: Int {
        guard budget > 0, left > 0, daysLeft > 0 else { return 0 }
        return left / daysLeft
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
    func monthTotals(count: Int, now: Date = Date(), calendar: Calendar = .kakeibo) -> [MonthTotal] {
        let thisMonth = Ledger.monthInterval(containing: now, calendar: calendar).start
        return (0..<count).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { return nil }
            let interval = Ledger.monthInterval(containing: start, calendar: calendar)
            return MonthTotal(start: start, spent: totalSpending(in: interval), isCurrent: back == 0)
        }
    }
}

/// Sections of Home that can be reordered or hidden.
enum HomeSection: String, CaseIterable, Identifiable {
    case bills, recent, budgets, partner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bills: return "Upcoming bills"
        case .recent: return "Recent"
        case .budgets: return "Budgets"
        case .partner: return "Partner balance"
        }
    }

    var symbol: String {
        switch self {
        case .bills: return "calendar"
        case .recent: return "list.bullet"
        case .budgets: return "chart.pie"
        case .partner: return "heart"
        }
    }

    static let defaultOrder = "bills,recent,budgets,partner"

    /// Stored order, with any unknown names dropped and new sections added at the end.
    static func order(from stored: String) -> [HomeSection] {
        var result: [HomeSection] = []
        for name in stored.split(separator: ",") {
            if let section = HomeSection(rawValue: String(name)), !result.contains(section) {
                result.append(section)
            }
        }
        for section in allCases where !result.contains(section) {
            result.append(section)
        }
        return result
    }

    static func hidden(from stored: String) -> Set<HomeSection> {
        Set(stored.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) })
    }

    static func encode(_ sections: [HomeSection]) -> String {
        sections.map(\.rawValue).joined(separator: ",")
    }
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
