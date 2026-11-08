import Foundation

/// Something coming up for a money account: a future-dated entry or a card bill it pays.
struct UpcomingItem: Identifiable {
    enum Source {
        case entry(Entry)
        case bill(BillReminder)
    }

    let id: String
    let date: Date
    let source: Source
    /// Signed change to the account.
    let amount: Int
    let balanceAfter: Int
}

/// A bank, top-up or cash account looking back and ahead (Bank account artboard).
struct MoneyAccountForecast {
    /// Balance at the end of today.
    let today: Int
    /// End-of-day balances for the past `days` days, oldest first, ending today.
    let past: [(date: Date, balance: Int)]
    /// Projected end-of-day balances for the next `days` days, starting today.
    let future: [(date: Date, balance: Int)]
    /// Future-dated entries and unpaid card bills, soonest first, with the balance after each.
    let upcoming: [UpcomingItem]

    init(account: Account, ledger: Ledger, now: Date = Date(), days: Int = 28, upcomingDays: Int = 45,
         calendar: Calendar = .kakeibo) {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let horizon = calendar.date(byAdding: .day, value: upcomingDays, to: endOfToday) ?? endOfToday
        let todayBalance = ledger.balance(of: account, before: endOfToday)

        var pastSeries: [(date: Date, balance: Int)] = []
        for back in stride(from: days, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: startOfToday),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            pastSeries.append((day, ledger.balance(of: account, before: end)))
        }

        var changes: [(id: String, date: Date, source: UpcomingItem.Source, amount: Int)] = []
        for entry in ledger.entries where entry.date >= endOfToday && entry.date < horizon {
            let effect = Ledger.effect(of: entry, on: account.id)
            if effect != 0 { changes.append((entry.id.uuidString, entry.date, .entry(entry), effect)) }
        }
        for bill in Billing.reminders(ledger: ledger, now: now, calendar: calendar)
        where bill.payFrom?.id == account.id && bill.dueDate >= startOfToday && bill.dueDate < horizon {
            // Due today counts as still to come until the payoff is recorded.
            changes.append((bill.id, max(bill.dueDate, startOfToday), .bill(bill), -bill.due))
        }
        changes.sort { $0.date < $1.date }

        var running = todayBalance
        var items: [UpcomingItem] = []
        for change in changes {
            running += change.amount
            items.append(UpcomingItem(id: change.id, date: change.date, source: change.source,
                                      amount: change.amount, balanceAfter: running))
        }

        var futureSeries: [(date: Date, balance: Int)] = []
        for ahead in 0...days {
            guard let day = calendar.date(byAdding: .day, value: ahead, to: startOfToday),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let applied = items.filter { $0.date < end }.reduce(0) { $0 + $1.amount }
            futureSeries.append((day, todayBalance + applied))
        }

        today = todayBalance
        past = pastSeries
        future = futureSeries
        upcoming = items
    }

    /// The first card bill the account can't cover, if any.
    var firstShortBill: UpcomingItem? {
        upcoming.first { item in
            if case .bill = item.source { return item.balanceAfter < 0 }
            return false
        }
    }

    var paysBills: Bool {
        upcoming.contains { item in
            if case .bill = item.source { return true }
            return false
        }
    }
}

/// A closed statement of a card and how it was settled (Credit card artboard, "Past statements").
struct PastStatement: Identifiable {
    let cycle: BillCycle
    /// Owed when the statement closed.
    let amount: Int
    /// Still unpaid now.
    let due: Int
    /// The payment that settled it, if one was recorded.
    let payment: Entry?

    var id: String { "\(cycle.year)-\(cycle.month)" }
    var isPaid: Bool { due == 0 }
}

enum CardHistory {
    /// The `count` statements before the latest one, newest first (the latest is "Current bill").
    static func pastStatements(for card: Account, ledger: Ledger, now: Date = Date(), count: Int = 3,
                               calendar: Calendar = .kakeibo) -> [PastStatement] {
        let rule = card.billingRule
        let latest = Billing.latestCycle(rule: rule, now: now, calendar: calendar)
        var result: [PastStatement] = []
        for back in 1...max(count, 1) {
            let cycle = Billing.shifted(latest, by: -back, rule: rule, calendar: calendar)
            let amount = Billing.statementTotal(for: card, cycle: cycle, ledger: ledger)
            guard amount > 0 else { continue }
            let next = Billing.shifted(cycle, by: 1, rule: rule, calendar: calendar)
            let key = cycle.key(for: card.id)
            let payment = ledger.entries
                .filter { entry in
                    guard entry.toAccountID == card.id, entry.kind == .payoff || entry.kind == .transfer else { return false }
                    if let entryKey = entry.billCycleKey { return entryKey == key }
                    return entry.date >= cycle.closingBoundary && entry.date < next.closingBoundary
                }
                .max { $0.date < $1.date }
            result.append(PastStatement(cycle: cycle, amount: amount,
                                        due: Billing.due(for: card, cycle: cycle, ledger: ledger), payment: payment))
        }
        return result
    }

    /// Entries charged to the card in a cycle, newest first.
    static func entries(of card: Account, in cycle: BillCycle, ledger: Ledger) -> [Entry] {
        ledger.entries
            .filter { $0.accountID == card.id && $0.kind == .expense && $0.date >= cycle.start && $0.date < cycle.closingBoundary }
            .sorted { $0.date > $1.date }
    }
}

/// How much of a card's credit limit is in use: everything owed, billed or not.
struct LimitUsage: Equatable {
    let owed: Int
    let limit: Int
    /// 0 when the alert is off.
    let alertPercent: Int

    var available: Int { limit - owed }
    var fraction: Double { limit > 0 ? Double(owed) / Double(limit) : 0 }
    /// Rounded down, so 44.9% doesn't show as 45% before the alert fires.
    var percent: Int { limit > 0 ? owed * 100 / limit : 0 }
    var alertFraction: Double? { alertPercent > 0 ? Double(alertPercent) / 100 : nil }
    /// Owed amount at which the alert fires.
    var alertAmount: Int? { alertPercent > 0 ? (limit * alertPercent + 99) / 100 : nil }
    var isPastAlert: Bool { alertAmount.map { owed >= $0 } ?? false }
}

extension Account {
    /// Limit usage for a credit card with a limit, nil otherwise.
    func limitUsage(ledger: Ledger, now: Date = Date()) -> LimitUsage? {
        guard kind == .credit, creditLimit > 0 else { return nil }
        let owed = max(-ledger.balance(of: self, before: now), 0)
        return LimitUsage(owed: owed, limit: creditLimit, alertPercent: min(max(limitAlertPercent, 0), 100))
    }

    /// What a card has left to spend, nil without a limit.
    func available(ledger: Ledger) -> Int? {
        limitUsage(ledger: ledger)?.available
    }
}

enum CreditLimits {
    /// Active cards whose owed amount has reached their alert percentage, most used first.
    static func pastAlert(ledger: Ledger, now: Date = Date()) -> [(card: Account, usage: LimitUsage)] {
        ledger.accounts
            .filter { $0.kind == .credit && !$0.isArchived }
            .compactMap { card in card.limitUsage(ledger: ledger, now: now).map { (card: card, usage: $0) } }
            .filter { $0.usage.isPastAlert }
            .sorted { $0.usage.fraction > $1.usage.fraction }
    }

    /// True when adding `amount` to what's owed takes the card from below its alert to at or past it.
    static func crosses(_ usage: LimitUsage, adding amount: Int) -> Bool {
        guard let threshold = usage.alertAmount, amount > 0 else { return false }
        return usage.owed >= threshold && usage.owed - amount < threshold
    }
}
