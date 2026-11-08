import Foundation

/// Card installments (分割払い): a purchase billed over several statements.
enum Installments {
    /// Counts Japanese cards offer; a custom count is allowed too.
    static let standardCounts = [2, 3, 5, 6, 10, 12, 15, 18, 20, 24, 30, 36]
    static let maxCount = 120

    /// Splits `total` into `count` parts; the remainder goes on the first, as card companies do
    /// (¥100,000 over 3 → 33,334 + 33,333 + 33,333).
    static func split(_ total: Int, into count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let base = total / count
        let remainder = total - base * count
        return (0..<count).map { $0 == 0 ? base + remainder : base }
    }

    /// Total fee at an annual rate with level payments (元利均等), the way Japanese card fee tables are
    /// built. Two installments are free; so is a zero rate.
    static func fee(principal: Int, months: Int, annualRate: Double) -> Int {
        guard months > 2, annualRate > 0, principal > 0 else { return 0 }
        let rate = annualRate / 100 / 12
        let payment = Double(principal) * rate / (1 - pow(1 + rate, -Double(months)))
        return max(Int((payment * Double(months) - Double(principal)).rounded()), 0)
    }

    /// The fee a purchase pays: its exact override, or the card's rate.
    static func fee(for entry: Entry, card: Account) -> Int {
        guard entry.installmentCount >= 2 else { return 0 }
        if entry.installmentFeeOverride >= 0 { return entry.installmentFeeOverride }
        return fee(principal: entry.amount, months: entry.installmentCount, annualRate: card.installmentFeeRate)
    }
}

/// One installment of a plan.
struct InstallmentSlice {
    /// 1-based.
    let number: Int
    /// The statement it's billed on.
    let cycle: BillCycle
    let principal: Int
    /// My part of `principal` (partner shares are owed back in full at once).
    let myShare: Int
    let fee: Int
    /// Billed before the card was added to Kakeibo: treated as already paid, outside the app.
    let isBeforeTracking: Bool

    var paymentDate: Date { cycle.paymentDate }
    var total: Int { principal + fee }
}

/// A purchase's installment schedule.
struct InstallmentPlan {
    let entry: Entry
    let card: Account
    let slices: [InstallmentSlice]

    var count: Int { entry.installmentCount }
    var mode: InstallmentMode { entry.installmentMode }
    var totalFee: Int { slices.reduce(0) { $0 + $1.fee } }
    var isPaidOff: Bool { entry.installmentPaidOffAt != nil }
    /// The usual monthly amount (the first one carries the rounding remainder).
    var regularPayment: Int { slices.count > 1 ? slices[1].total : (slices.first?.total ?? 0) }

    init?(entry: Entry, card: Account, calendar: Calendar = .kakeibo) {
        guard entry.isInstallment, card.kind == .credit else { return nil }
        let count = min(entry.installmentCount, Installments.maxCount)
        let rule = card.billingRule
        let first = Billing.cycle(containing: entry.date, rule: rule, calendar: calendar)
        let principals = Installments.split(entry.amount, into: count)
        let mine = Installments.split(entry.isRefund ? 0 : entry.myShare, into: count)
        let fees = Installments.split(Installments.fee(for: entry, card: card), into: count)
        let tracked = calendar.startOfDay(for: card.createdAt)
        let payoffCycle = entry.installmentPaidOffAt.map { Billing.cycle(containing: $0, rule: rule, calendar: calendar) }

        var slices: [InstallmentSlice] = []
        for index in 0..<count {
            var cycle = Billing.shifted(first, by: index, rule: rule, calendar: calendar)
            var fee = fees[index]
            // "Pay off the rest": anything not yet billed lands on the bill open that day, without fees.
            if let paidOff = entry.installmentPaidOffAt, let payoffCycle, cycle.closingBoundary > paidOff {
                cycle = payoffCycle
                fee = 0
            }
            slices.append(InstallmentSlice(number: index + 1, cycle: cycle, principal: principals[index],
                                           myShare: mine[index], fee: fee,
                                           isBeforeTracking: cycle.paymentDate < tracked))
        }
        self.entry = entry
        self.card = card
        self.slices = slices
    }

    /// Installments paid by `date`.
    func paidCount(by date: Date) -> Int {
        slices.filter { $0.paymentDate <= date }.count
    }

    /// Principal and fees still to pay after `date`.
    func remaining(after date: Date) -> Int {
        slices.filter { $0.paymentDate > date }.reduce(0) { $0 + $1.total }
    }

    func isFinished(by date: Date) -> Bool { paidCount(by: date) == slices.count }

    /// The installments billed on a statement.
    func slices(on cycle: BillCycle) -> [InstallmentSlice] {
        slices.filter { $0.cycle.year == cycle.year && $0.cycle.month == cycle.month }
    }

    /// The first statement has closed: the plan can no longer be changed, only paid off.
    func isLocked(now: Date) -> Bool {
        guard let first = slices.first else { return false }
        return first.cycle.closingBoundary <= now
    }
}
