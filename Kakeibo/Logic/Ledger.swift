import Foundation

extension Calendar {
    /// Gregorian calendar in the phone's time zone, used for all month and billing maths.
    static var kakeibo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }
}

/// Pure calculations over accounts, categories and entries.
struct Ledger {
    let accounts: [Account]
    let categories: [BudgetCategory]
    let entries: [Entry]
    /// Installment schedules of card purchases paid in installments.
    let installmentPlans: [InstallmentPlan]

    init(accounts: [Account], categories: [BudgetCategory] = [], entries: [Entry]) {
        self.accounts = accounts
        self.categories = categories
        self.entries = entries
        let cards = Dictionary(accounts.filter { $0.kind == .credit }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        installmentPlans = entries.compactMap { entry in
            guard entry.isInstallment, let id = entry.accountID, let card = cards[id] else { return nil }
            return InstallmentPlan(entry: entry, card: card)
        }
    }

    func plan(for entry: Entry) -> InstallmentPlan? {
        installmentPlans.first { $0.entry.id == entry.id }
    }

    func account(_ id: UUID?) -> Account? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    // MARK: Balances

    /// How an entry changes an account's value. Credit accounts go negative as you spend.
    static func effect(of entry: Entry, on accountID: UUID) -> Int {
        var delta = 0
        switch entry.kind {
        case .expense:
            if entry.accountID == accountID { delta += entry.isRefund ? entry.amount : -entry.amount }
        case .income, .settlement, .adjust:
            if entry.accountID == accountID { delta += entry.amount }
        case .transfer, .payoff:
            if entry.accountID == accountID { delta -= entry.amount }
            if entry.toAccountID == accountID { delta += entry.received }
        }
        return delta
    }

    /// Account value from its opening balance plus every entry dated before `cutoff` (all entries if nil).
    /// For credit accounts the value is negative: `-balance` is what is owed.
    func balance(of account: Account, before cutoff: Date? = nil) -> Int {
        var total = account.openingBalance
        for entry in entries {
            if let cutoff, entry.date >= cutoff { continue }
            total += Ledger.effect(of: entry, on: account.id)
        }
        if account.kind == .credit {
            total += installmentAdjustment(for: account, before: cutoff)
        }
        return total
    }

    /// Installments change a card's balance beyond the purchase itself (which owes the full price):
    /// each fee is charged when its statement closes, and installments billed before the card was added
    /// to Kakeibo were paid outside the app.
    private func installmentAdjustment(for card: Account, before cutoff: Date?) -> Int {
        var total = 0
        for plan in installmentPlans where plan.card.id == card.id {
            for slice in plan.slices {
                if slice.isBeforeTracking {
                    if cutoff.map({ slice.paymentDate < $0 }) ?? true { total += slice.principal }
                } else if slice.fee > 0, cutoff.map({ slice.cycle.closingBoundary <= $0 }) ?? true {
                    total -= slice.fee
                }
            }
        }
        return total
    }

    /// Installment principal on a card that is owed but billed on statements after `cycle`.
    func deferredPrincipal(for card: Account, after cycle: BillCycle) -> Int {
        var total = 0
        for plan in installmentPlans where plan.card.id == card.id && plan.entry.date < cycle.closingBoundary {
            for slice in plan.slices where slice.cycle.closingBoundary > cycle.closingBoundary {
                total += slice.principal
            }
        }
        return total
    }

    // MARK: Months

    static func monthInterval(containing date: Date, calendar: Calendar = .kakeibo) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
    }

    private func isIn(_ entry: Entry, _ interval: DateInterval) -> Bool {
        entry.date >= interval.start && entry.date < interval.end
    }

    // MARK: Spending

    /// My spending per category. Partner shares, transfers and payoffs are excluded;
    /// refunds reduce spending; top-ups into "counts as spending" accounts (PASMO) count, and so do
    /// transfer fees (in "Bank fees").
    func spendingByCategory(in interval: DateInterval) -> [UUID: Int] {
        var topUpCategory: [UUID: UUID] = [:]
        for account in accounts where account.kind == .topUp && account.countsTopUpAsSpending {
            if let categoryID = account.topUpCategoryID { topUpCategory[account.id] = categoryID }
        }
        var result: [UUID: Int] = [:]
        let bankFees = bankFeesCategoryID
        for entry in entries where isIn(entry, interval) {
            switch entry.kind {
            case .expense:
                guard let categoryID = entry.categoryID else { continue }
                // Installment purchases that count monthly (or never) are added per installment below.
                if entry.isInstallment, entry.installmentMode != .all, plan(for: entry) != nil { continue }
                let value = entry.isRefund ? -entry.amount : entry.myShare
                result[categoryID, default: 0] += value
            case .transfer:
                if let to = entry.toAccountID, let categoryID = topUpCategory[to] {
                    result[categoryID, default: 0] += entry.received
                }
                if entry.feePaid > 0, let bankFees {
                    result[bankFees, default: 0] += entry.feePaid
                }
            default:
                continue
            }
        }
        let feeCategory = cardFeesCategoryID
        for plan in installmentPlans {
            for slice in plan.slices where slice.paymentDate >= interval.start && slice.paymentDate < interval.end {
                if plan.mode == .monthly, let categoryID = plan.entry.categoryID {
                    result[categoryID, default: 0] += slice.myShare
                }
                if slice.fee > 0, let feeCategory {
                    result[feeCategory, default: 0] += slice.fee
                }
            }
        }
        return result
    }

    /// The category installment fees count in ("Card fees", created when first needed).
    var cardFeesCategoryID: UUID? {
        categories.first { $0.kind == .expense && $0.name.lowercased() == Ledger.cardFeesName.lowercased() }?.id
    }

    static let cardFeesName = "Card fees"

    /// The category transfer fees count in ("Bank fees", created when first needed).
    var bankFeesCategoryID: UUID? {
        categories.first { $0.kind == .expense && $0.name.lowercased() == Ledger.bankFeesName.lowercased() }?.id
    }

    static let bankFeesName = "Bank fees"

    /// Transfers that paid a fee in `interval`, newest first: what "Bank fees" lists.
    func feeTransfers(in interval: DateInterval) -> [Entry] {
        entries.filter { $0.feePaid > 0 && isIn($0, interval) }.sorted { $0.date > $1.date }
    }

    /// The last fee and how it was entered for transfers from `from` to `to`, for the editor's suggestion.
    func lastTransferFee(from: UUID?, to: UUID?, excluding id: UUID? = nil) -> (fee: Int, onTop: Bool)? {
        guard let from, let to else { return nil }
        let last = entries
            .filter { $0.kind == .transfer && $0.accountID == from && $0.toAccountID == to && $0.feePaid > 0 && $0.id != id }
            .max { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        return last.map { (fee: $0.feePaid, onTop: $0.transferFeeOnTop) }
    }

    func totalSpending(in interval: DateInterval) -> Int {
        spendingByCategory(in: interval).values.reduce(0, +)
    }

    func incomeByCategory(in interval: DateInterval) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for entry in entries where entry.kind == .income && isIn(entry, interval) {
            guard let categoryID = entry.categoryID else { continue }
            result[categoryID, default: 0] += entry.amount
        }
        return result
    }

    // MARK: Partner

    var sharedExpenses: [Entry] {
        entries
            .filter { $0.isSharedExpense }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    var settlements: [Entry] {
        entries.filter { $0.kind == .settlement }.sorted { $0.date > $1.date }
    }

    /// Total my partner still owes. Negative means she has paid back more than owed.
    var partnerOwed: Int {
        let owed = sharedExpenses.reduce(0) { $0 + $1.partnerShare }
        let repaid = settlements.reduce(0) { $0 + $1.amount }
        return owed - repaid
    }

    /// What's still unpaid on each shared expense. Targeted repayments ("mark repaid") apply to
    /// their item first; everything else pays off the oldest items first.
    func partnerRemaining() -> [UUID: Int] {
        let items = sharedExpenses
        var remaining: [UUID: Int] = [:]
        for item in items { remaining[item.id] = item.partnerShare }

        var pool = 0
        for settlement in settlements {
            if let target = settlement.settlementTargetID, let left = remaining[target] {
                let used = min(left, settlement.amount)
                remaining[target] = left - used
                pool += settlement.amount - used
            } else {
                pool += settlement.amount
            }
        }
        for item in items where pool > 0 {
            let left = remaining[item.id] ?? 0
            let used = min(left, pool)
            remaining[item.id] = left - used
            pool -= used
        }
        return remaining
    }
}

/// Fast name lookups for list rows.
struct Lookup {
    let accounts: [UUID: Account]
    let categories: [UUID: BudgetCategory]

    init(accounts: [Account], categories: [BudgetCategory]) {
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.categories = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func accountName(_ id: UUID?) -> String {
        guard let id, let account = accounts[id] else { return "No account" }
        return account.name
    }

    func category(_ id: UUID?) -> BudgetCategory? {
        guard let id else { return nil }
        return categories[id]
    }
}
