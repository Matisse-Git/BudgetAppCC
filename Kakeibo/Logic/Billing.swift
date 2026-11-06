import Foundation
import SwiftData

/// One statement cycle of a credit account: purchases up to the closing day (締め日) are paid on the
/// payment day (支払日) of a later month, moved off weekends and bank holidays per the card's rule.
struct BillCycle: Equatable {
    /// Year and month the statement closes in.
    let year: Int
    let month: Int
    /// Start of the first day on this statement (the day after the previous closing day).
    let start: Date
    /// Start of the closing day.
    let closingDate: Date
    /// Start of the day after the closing day. Purchases before this are on this bill.
    let closingBoundary: Date
    /// The payment day as written in the card's terms.
    let nominalPaymentDate: Date
    /// The day the money actually leaves (start of day).
    let paymentDate: Date

    func key(for accountID: UUID) -> String {
        "\(accountID.uuidString)-\(year)-\(month)"
    }

    /// True when the payment moved because the nominal day was a weekend or a bank holiday.
    var isShifted: Bool { nominalPaymentDate != paymentDate }
}

/// Why a payment moved.
enum PaymentShiftCause: Equatable {
    case weekend(weekday: String)
    case holiday(name: String)
}

struct CardStatus {
    /// The latest closed statement.
    let cycle: BillCycle
    /// The statement building up now.
    let next: BillCycle
    /// Amount on the closed statement that is still unpaid.
    let due: Int
    let dueDate: Date
    /// Purchases since the last closing day.
    let nextSoFar: Int
    let nextDueDate: Date
    let isOverdue: Bool
    /// Everything currently owed on the card, billed or not.
    let owedNow: Int
}

/// An unpaid, closed statement and whether the account that pays it will cover it.
struct BillReminder: Identifiable {
    let id: String
    let account: Account
    let cycle: BillCycle
    let due: Int
    let dueDate: Date
    let payFrom: Account?
    /// The paying account's balance on the due date, counting future-dated entries (scheduled income)
    /// but before any of the card bills it pays.
    let projectedBalance: Int
    /// How much the paying account is short on the due date, counting earlier bills it also pays.
    /// Zero when the card's shortfall warning is off.
    let shortfall: Int
    let isOverdue: Bool
}

/// A statement that closed, for the Activity feed ("Travel Card statement closed").
struct StatementEvent: Identifiable {
    let account: Account
    let cycle: BillCycle
    /// Owed on the card when the statement closed.
    let amount: Int

    var id: String { cycle.key(for: account.id) }
}

enum Billing {
    static let processedKey = "processedBillCycles"

    // MARK: Dates

    static func day(_ day: Int, year: Int, month: Int, calendar: Calendar = .kakeibo) -> Date {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        let clamped = min(max(day, 1), length)
        return calendar.date(from: DateComponents(year: year, month: month, day: clamped)) ?? first
    }

    /// Year and month `months` away from the given one.
    static func addMonths(_ months: Int, toYear year: Int, month: Int) -> (year: Int, month: Int) {
        let total = max(year * 12 + (month - 1) + months, 0)
        return (total / 12, total % 12 + 1)
    }

    /// Moves a nominal payment day off weekends and bank holidays.
    static func adjust(_ date: Date, _ shift: HolidayShift, calendar: Calendar = .kakeibo) -> Date {
        switch shift {
        case .nextBusinessDay: return JapaneseHolidays.nextBusinessDay(onOrAfter: date, calendar: calendar)
        case .previousBusinessDay: return JapaneseHolidays.previousBusinessDay(onOrBefore: date, calendar: calendar)
        case .none: return calendar.startOfDay(for: date)
        }
    }

    static func cycle(year: Int, month: Int, rule: BillingRule, calendar: Calendar = .kakeibo) -> BillCycle {
        let closing = day(rule.closingDay, year: year, month: month, calendar: calendar)
        let boundary = calendar.date(byAdding: .day, value: 1, to: closing) ?? closing
        let previous = addMonths(-1, toYear: year, month: month)
        let previousClosing = day(rule.closingDay, year: previous.year, month: previous.month, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: 1, to: previousClosing) ?? previousClosing

        let offset = min(max(rule.paymentMonthOffset, 0), 2)
        var pay = addMonths(offset, toYear: year, month: month)
        var nominal = day(rule.paymentDay, year: pay.year, month: pay.month, calendar: calendar)
        if nominal < boundary {
            // "Same month" with a payment day before closing: it can only mean the month after.
            pay = addMonths(1, toYear: pay.year, month: pay.month)
            nominal = day(rule.paymentDay, year: pay.year, month: pay.month, calendar: calendar)
        }
        return BillCycle(
            year: year,
            month: month,
            start: start,
            closingDate: closing,
            closingBoundary: boundary,
            nominalPaymentDate: nominal,
            paymentDate: adjust(nominal, rule.shift, calendar: calendar)
        )
    }

    /// A cycle closing on `closingDay` and paid on `paymentDay` of the next month, moved to the next
    /// business day when needed.
    static func cycle(year: Int, month: Int, closingDay: Int, paymentDay: Int, calendar: Calendar = .kakeibo) -> BillCycle {
        cycle(year: year, month: month, rule: BillingRule(closingDay: closingDay, paymentDay: paymentDay), calendar: calendar)
    }

    static func shifted(_ cycle: BillCycle, by months: Int, rule: BillingRule, calendar: Calendar = .kakeibo) -> BillCycle {
        let target = addMonths(months, toYear: cycle.year, month: cycle.month)
        return Billing.cycle(year: target.year, month: target.month, rule: rule, calendar: calendar)
    }

    /// The most recent cycle whose closing day has passed.
    static func latestCycle(for account: Account, now: Date, calendar: Calendar = .kakeibo) -> BillCycle {
        latestCycle(rule: account.billingRule, now: now, calendar: calendar)
    }

    static func latestCycle(rule: BillingRule, now: Date, calendar: Calendar = .kakeibo) -> BillCycle {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let current = cycle(year: parts.year ?? 2026, month: parts.month ?? 1, rule: rule, calendar: calendar)
        if current.closingBoundary > now {
            return shifted(current, by: -1, rule: rule, calendar: calendar)
        }
        return current
    }

    /// The cycle a purchase on `date` belongs to.
    static func cycle(containing date: Date, rule: BillingRule, calendar: Calendar = .kakeibo) -> BillCycle {
        let latest = latestCycle(rule: rule, now: date, calendar: calendar)
        return shifted(latest, by: 1, rule: rule, calendar: calendar)
    }

    /// Why a cycle's payment moved, nil if it didn't.
    static func shiftCause(of cycle: BillCycle, calendar: Calendar = .kakeibo) -> PaymentShiftCause? {
        guard cycle.isShifted else { return nil }
        let nominal = cycle.nominalPaymentDate
        if JapaneseHolidays.isWeekend(nominal, calendar: calendar) {
            return .weekend(weekday: nominal.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)))
        }
        if let name = JapaneseHolidays.name(of: nominal, calendar: calendar) {
            return .holiday(name: name)
        }
        return nil
    }

    // MARK: Amounts

    /// What is still unpaid from a cycle's statement: owed at closing minus payoffs made after closing
    /// (and before `cutoff`) that aren't tied to a different cycle.
    static func due(for account: Account, cycle: BillCycle, ledger: Ledger, before cutoff: Date = .distantFuture) -> Int {
        let owedAtClose = -ledger.balance(of: account, before: cycle.closingBoundary)
        let key = cycle.key(for: account.id)
        var paid = 0
        for entry in ledger.entries where entry.date >= cycle.closingBoundary && entry.date < cutoff {
            guard entry.toAccountID == account.id, entry.kind == .payoff || entry.kind == .transfer else { continue }
            if let entryKey = entry.billCycleKey, entryKey != key { continue }
            paid += entry.amount
        }
        return max(0, owedAtClose - paid)
    }

    static func status(for account: Account, ledger: Ledger, now: Date = Date(), calendar: Calendar = .kakeibo) -> CardStatus {
        let rule = account.billingRule
        let cycle = latestCycle(rule: rule, now: now, calendar: calendar)
        let next = shifted(cycle, by: 1, rule: rule, calendar: calendar)
        let dueAmount = due(for: account, cycle: cycle, ledger: ledger)
        let owedNow = -ledger.balance(of: account)
        let dayAfterPayment = calendar.date(byAdding: .day, value: 1, to: cycle.paymentDate) ?? cycle.paymentDate
        return CardStatus(
            cycle: cycle,
            next: next,
            due: dueAmount,
            dueDate: cycle.paymentDate,
            nextSoFar: max(0, owedNow - dueAmount),
            nextDueDate: next.paymentDate,
            isOverdue: dueAmount > 0 && now >= dayAfterPayment,
            owedNow: owedNow
        )
    }

    /// Statements of active cards that closed after `start` and by `end`, newest first.
    static func closedStatements(ledger: Ledger, from start: Date, to end: Date, calendar: Calendar = .kakeibo) -> [StatementEvent] {
        var events: [StatementEvent] = []
        for account in ledger.accounts where account.kind == .credit && !account.isArchived {
            let rule = account.billingRule
            var cycle = latestCycle(rule: rule, now: end, calendar: calendar)
            for _ in 0..<36 {
                guard cycle.closingBoundary > start else { break }
                let owed = -ledger.balance(of: account, before: cycle.closingBoundary)
                if owed > 0 { events.append(StatementEvent(account: account, cycle: cycle, amount: owed)) }
                cycle = shifted(cycle, by: -1, rule: rule, calendar: calendar)
            }
        }
        return events.sorted { $0.cycle.closingDate > $1.cycle.closingDate }
    }

    // MARK: Reminders and shortfalls

    /// Every unpaid, closed statement (or only those due within `windowDays`), soonest first, with the
    /// paying account's projected balance and shortfall on the due date. A bill shows up as soon as its
    /// statement closes.
    static func reminders(ledger: Ledger, now: Date = Date(), windowDays: Int? = nil, calendar: Calendar = .kakeibo) -> [BillReminder] {
        let today = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let horizon = windowDays.flatMap { calendar.date(byAdding: .day, value: $0, to: today) }
        var items: [(Account, CardStatus)] = []
        for account in ledger.accounts where account.kind == .credit && !account.isArchived {
            let state = status(for: account, ledger: ledger, now: now, calendar: calendar)
            guard state.due > 0 else { continue }
            if let horizon, state.dueDate > horizon { continue }
            items.append((account, state))
        }
        items.sort { $0.1.dueDate < $1.1.dueDate }

        var committed: [UUID: Int] = [:]
        var reminders: [BillReminder] = []
        for (account, state) in items {
            let payFrom = ledger.account(account.payFromAccountID)
            var projected = 0
            var shortfall = 0
            if let payFrom {
                let endOfDueDay = calendar.date(byAdding: .day, value: 1, to: state.dueDate) ?? state.dueDate
                projected = ledger.balance(of: payFrom, before: max(endOfDueDay, endOfToday))
                committed[payFrom.id, default: 0] += state.due
                if account.shortfallWarning {
                    shortfall = max(0, (committed[payFrom.id] ?? 0) - projected)
                }
            }
            reminders.append(BillReminder(
                id: state.cycle.key(for: account.id),
                account: account,
                cycle: state.cycle,
                due: state.due,
                dueDate: state.dueDate,
                payFrom: payFrom,
                projectedBalance: projected,
                shortfall: shortfall,
                isOverdue: state.isOverdue
            ))
        }
        return reminders
    }

    /// The account to top up `payer` from: the other money account with the most in it today, preferring
    /// one that can cover `amount` on its own.
    static func suggestedSource(for payer: Account, amount: Int, ledger: Ledger, now: Date = Date(),
                                calendar: Calendar = .kakeibo) -> Account? {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let balances = ledger.accounts
            .filter { $0.holdsMoney && !$0.isArchived && $0.id != payer.id }
            .map { (account: $0, balance: ledger.balance(of: $0, before: endOfToday)) }
        let covering = balances.filter { $0.balance >= amount }
        return (covering.isEmpty ? balances : covering).max { $0.balance < $1.balance }?.account
    }

    /// When the reminders for a bill go out: 9:00, three days and one day before it's due (future ones only).
    static func reminderDates(dueDate: Date, now: Date = Date(), calendar: Calendar = .kakeibo) -> [Date] {
        [3, 1].compactMap { daysBefore in
            guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: dueDate),
                  let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                  fire > now else { return nil }
            return fire
        }
    }

    // MARK: Automatic payoffs

    /// On (or after) a payment day, records the card payoff the bank makes automatically, as a transfer
    /// from the paying account. Each cycle is handled once, so deleting an automatic payoff doesn't bring
    /// it back.
    @MainActor
    @discardableResult
    static func runAutoPayoffs(context: ModelContext, accounts: [Account], entries: [Entry], now: Date = Date(),
                               defaults: UserDefaults = .standard, calendar: Calendar = .kakeibo) -> Int {
        var processed = Set(defaults.stringArray(forKey: processedKey) ?? [])
        var allEntries = entries
        var created = 0

        for account in accounts where account.kind == .credit && !account.isArchived && account.autoPayoff {
            guard let payFrom = account.payFromAccountID else { continue }
            let rule = account.billingRule
            let setupDay = calendar.startOfDay(for: account.createdAt)
            var cycles: [BillCycle] = []
            var cycle = latestCycle(rule: rule, now: now, calendar: calendar)
            for _ in 0..<4 {
                cycles.append(cycle)
                cycle = shifted(cycle, by: -1, rule: rule, calendar: calendar)
            }
            for cycle in cycles.reversed() {
                let key = cycle.key(for: account.id)
                guard cycle.paymentDate <= now, cycle.paymentDate >= setupDay, !processed.contains(key) else { continue }
                processed.insert(key)
                if allEntries.contains(where: { $0.billCycleKey == key }) { continue }

                let ledger = Ledger(accounts: accounts, entries: allEntries)
                let endOfPaymentDay = calendar.date(byAdding: .day, value: 1, to: cycle.paymentDate) ?? cycle.paymentDate
                let amount = due(for: account, cycle: cycle, ledger: ledger, before: endOfPaymentDay)
                guard amount > 0 else { continue }

                let date = calendar.date(byAdding: .hour, value: 9, to: cycle.paymentDate) ?? cycle.paymentDate
                let payoff = Entry(kind: .payoff, amount: amount, date: date, accountID: payFrom, toAccountID: account.id)
                payoff.isConfirmed = false
                payoff.isAutoCreated = true
                payoff.billCycleKey = key
                payoff.note = "\(account.name) bill"
                context.insert(payoff)
                allEntries.append(payoff)
                created += 1
            }
        }
        defaults.set(Array(processed), forKey: processedKey)
        return created
    }
}

/// "1st", "2nd", "27th"; "end of month" for 31.
enum Ordinal {
    static func day(_ value: Int, endOfMonth: String = "end of month") -> String {
        if value >= 31 { return endOfMonth }
        let suffix: String
        switch value % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch value % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(value)\(suffix)"
    }
}
