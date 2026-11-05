import Foundation
import SwiftData

/// One statement cycle of a credit account: purchases up to the closing day are paid
/// on the payment day of the following month.
struct BillCycle: Equatable {
    /// Year and month the statement closes in.
    let year: Int
    let month: Int
    /// Start of the day after the closing day. Purchases before this are on this bill.
    let closingBoundary: Date
    /// Start of the payment day.
    let paymentDate: Date

    func key(for accountID: UUID) -> String {
        "\(accountID.uuidString)-\(year)-\(month)"
    }
}

struct CardStatus {
    /// Amount on the closed statement that is still unpaid.
    let due: Int
    let dueDate: Date
    /// Purchases since the last closing day.
    let nextSoFar: Int
    let nextDueDate: Date
    let isOverdue: Bool
    /// Everything currently owed on the card.
    let owedNow: Int
}

struct BillReminder: Identifiable {
    let id: String
    let account: Account
    let due: Int
    let dueDate: Date
    let payFrom: Account?
    /// How much the paying account is short, counting earlier bills it also pays.
    let shortfall: Int
    let isOverdue: Bool
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

    static func cycle(year: Int, month: Int, closingDay: Int, paymentDay: Int, calendar: Calendar = .kakeibo) -> BillCycle {
        let closing = day(closingDay, year: year, month: month, calendar: calendar)
        let boundary = calendar.date(byAdding: .day, value: 1, to: closing) ?? closing
        var payYear = year
        var payMonth = month + 1
        if payMonth > 12 { payMonth = 1; payYear += 1 }
        let payment = day(paymentDay, year: payYear, month: payMonth, calendar: calendar)
        return BillCycle(year: year, month: month, closingBoundary: boundary, paymentDate: payment)
    }

    static func shifted(_ cycle: BillCycle, by months: Int, closingDay: Int, paymentDay: Int, calendar: Calendar = .kakeibo) -> BillCycle {
        var total = cycle.year * 12 + (cycle.month - 1) + months
        if total < 0 { total = 0 }
        return Billing.cycle(year: total / 12, month: total % 12 + 1, closingDay: closingDay, paymentDay: paymentDay, calendar: calendar)
    }

    /// The most recent cycle whose closing day has passed.
    static func latestCycle(for account: Account, now: Date, calendar: Calendar = .kakeibo) -> BillCycle {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let current = cycle(year: parts.year ?? 2026, month: parts.month ?? 1,
                            closingDay: account.closingDay, paymentDay: account.paymentDay, calendar: calendar)
        if current.closingBoundary > now {
            return shifted(current, by: -1, closingDay: account.closingDay, paymentDay: account.paymentDay, calendar: calendar)
        }
        return current
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
        let cycle = latestCycle(for: account, now: now, calendar: calendar)
        let next = shifted(cycle, by: 1, closingDay: account.closingDay, paymentDay: account.paymentDay, calendar: calendar)
        let dueAmount = due(for: account, cycle: cycle, ledger: ledger)
        let owedNow = -ledger.balance(of: account)
        let dayAfterPayment = calendar.date(byAdding: .day, value: 1, to: cycle.paymentDate) ?? cycle.paymentDate
        return CardStatus(
            due: dueAmount,
            dueDate: cycle.paymentDate,
            nextSoFar: max(0, owedNow - dueAmount),
            nextDueDate: next.paymentDate,
            isOverdue: dueAmount > 0 && now >= dayAfterPayment,
            owedNow: owedNow
        )
    }

    // MARK: Reminders

    /// Unpaid bills due within `windowDays` (or overdue), with shortfall of the paying account.
    static func reminders(ledger: Ledger, now: Date = Date(), windowDays: Int = 7, calendar: Calendar = .kakeibo) -> [BillReminder] {
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: windowDays, to: today) ?? today
        var items: [(Account, CardStatus, BillCycle)] = []
        for account in ledger.accounts where account.kind == .credit && !account.isArchived {
            let state = status(for: account, ledger: ledger, now: now, calendar: calendar)
            guard state.due > 0, state.dueDate <= horizon else { continue }
            items.append((account, state, latestCycle(for: account, now: now, calendar: calendar)))
        }
        items.sort { $0.1.dueDate < $1.1.dueDate }

        var committed: [UUID: Int] = [:]
        var reminders: [BillReminder] = []
        for (account, state, cycle) in items {
            let payFrom = ledger.account(account.payFromAccountID)
            var shortfall = 0
            if let payFrom {
                committed[payFrom.id, default: 0] += state.due
                let available = ledger.balance(of: payFrom)
                shortfall = max(0, (committed[payFrom.id] ?? 0) - available)
            }
            reminders.append(BillReminder(
                id: cycle.key(for: account.id),
                account: account,
                due: state.due,
                dueDate: state.dueDate,
                payFrom: payFrom,
                shortfall: shortfall,
                isOverdue: state.isOverdue
            ))
        }
        return reminders
    }

    // MARK: Automatic payoffs

    /// On (or after) a payment day, records the card payoff the bank makes automatically.
    /// Each cycle is handled once, so deleting an automatic payoff doesn't bring it back.
    @MainActor
    @discardableResult
    static func runAutoPayoffs(context: ModelContext, accounts: [Account], entries: [Entry], now: Date = Date(),
                               defaults: UserDefaults = .standard, calendar: Calendar = .kakeibo) -> Int {
        var processed = Set(defaults.stringArray(forKey: processedKey) ?? [])
        var allEntries = entries
        var created = 0

        for account in accounts where account.kind == .credit && !account.isArchived && account.autoPayoff {
            guard let payFrom = account.payFromAccountID else { continue }
            let setupDay = calendar.startOfDay(for: account.createdAt)
            var cycles: [BillCycle] = []
            var cycle = latestCycle(for: account, now: now, calendar: calendar)
            for _ in 0..<4 {
                cycles.append(cycle)
                cycle = shifted(cycle, by: -1, closingDay: account.closingDay, paymentDay: account.paymentDay, calendar: calendar)
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
                payoff.note = "Automatic \(account.name) payment"
                context.insert(payoff)
                allEntries.append(payoff)
                created += 1
            }
        }
        defaults.set(Array(processed), forKey: processedKey)
        return created
    }
}
