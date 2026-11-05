import SwiftData
import XCTest
@testable import Kakeibo

private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    Calendar.kakeibo.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

final class YenTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(Yen.parse("¥1,234"), 1234)
        XCTAssertEqual(Yen.parse("￥１，２３４"), 1234)
        XCTAssertEqual(Yen.parse("1234.00"), 1234)
        XCTAssertEqual(Yen.parse("1.234,00"), 1234)
        XCTAssertEqual(Yen.parse("JPY 980"), 980)
        XCTAssertEqual(Yen.parse("12,000円"), 12000)
        XCTAssertEqual(Yen.parse("-500"), -500)
        XCTAssertNil(Yen.parse("abc"))
    }

    func testFormat() {
        XCTAssertEqual(Yen.format(1234), "¥1,234")
        XCTAssertEqual(Yen.format(-50), "−¥50")
        XCTAssertEqual(Yen.format(300, showPlus: true), "+¥300")
    }
}

final class LedgerTests: XCTestCase {
    func testSharedExpenseCountsOnlyMyShare() {
        let bank = Account(name: "SMBC bank", kind: .bank, openingBalance: 10_000)
        let food = BudgetCategory(name: "Restaurants", emoji: "🍜", kind: .expense, sortOrder: 0)
        let dinner = Entry(kind: .expense, amount: 4000, date: day(2026, 11, 3), accountID: bank.id, categoryID: food.id)
        dinner.partnerShare = 2000
        let ledger = Ledger(accounts: [bank], categories: [food], entries: [dinner])
        let month = Ledger.monthInterval(containing: day(2026, 11, 1))

        XCTAssertEqual(ledger.spendingByCategory(in: month)[food.id], 2000)
        XCTAssertEqual(ledger.partnerOwed, 2000)
        XCTAssertEqual(ledger.balance(of: bank), 6000, "The full amount leaves the account")
    }

    func testSettleUpPaysOldestFirst() {
        let bank = Account(name: "Bank", kind: .bank)
        let a = Entry(kind: .expense, amount: 2000, date: day(2026, 11, 1), accountID: bank.id)
        a.partnerShare = 1000
        let b = Entry(kind: .expense, amount: 6000, date: day(2026, 11, 2), accountID: bank.id)
        b.partnerShare = 3000
        let repay = Entry(kind: .settlement, amount: 2000, date: day(2026, 11, 4), accountID: bank.id)
        let ledger = Ledger(accounts: [bank], entries: [a, b, repay])

        let remaining = ledger.partnerRemaining()
        XCTAssertEqual(remaining[a.id], 0)
        XCTAssertEqual(remaining[b.id], 2000)
        XCTAssertEqual(ledger.partnerOwed, 2000)
        XCTAssertEqual(ledger.balance(of: bank), -8000 + 2000, "Repayment adds to the account")
    }

    func testMarkRepaidTargetsOneItem() {
        let bank = Account(name: "Bank", kind: .bank)
        let a = Entry(kind: .expense, amount: 2000, date: day(2026, 11, 1), accountID: bank.id)
        a.partnerShare = 1000
        let b = Entry(kind: .expense, amount: 6000, date: day(2026, 11, 2), accountID: bank.id)
        b.partnerShare = 3000
        let repay = Entry(kind: .settlement, amount: 3000, date: day(2026, 11, 4), accountID: bank.id)
        repay.settlementTargetID = b.id
        let remaining = Ledger(accounts: [bank], entries: [a, b, repay]).partnerRemaining()

        XCTAssertEqual(remaining[a.id], 1000)
        XCTAssertEqual(remaining[b.id], 0)
    }

    func testTransfersAreNotSpendingButPasmoTopUpsAre() {
        let transport = BudgetCategory(name: "Transport", emoji: "🚃", kind: .expense, sortOrder: 0)
        let bank = Account(name: "SMBC bank", kind: .bank, openingBalance: 100_000)
        let revolut = Account(name: "Revolut", kind: .topUp)
        let pasmo = Account(name: "PASMO", kind: .topUp)
        pasmo.countsTopUpAsSpending = true
        pasmo.topUpCategoryID = transport.id
        let topUp = Entry(kind: .transfer, amount: 30_000, date: day(2026, 11, 1), accountID: bank.id, toAccountID: revolut.id)
        let pasmoCharge = Entry(kind: .transfer, amount: 5000, date: day(2026, 11, 2), accountID: bank.id, toAccountID: pasmo.id)
        let ledger = Ledger(accounts: [bank, revolut, pasmo], categories: [transport], entries: [topUp, pasmoCharge])
        let month = Ledger.monthInterval(containing: day(2026, 11, 1))

        XCTAssertEqual(ledger.totalSpending(in: month), 5000)
        XCTAssertEqual(ledger.balance(of: bank), 65_000)
        XCTAssertEqual(ledger.balance(of: revolut), 30_000)
    }

    func testRefundReducesSpending() {
        let card = Account(name: "Rakuten", kind: .credit)
        let shopping = BudgetCategory(name: "Shopping", emoji: "🛍️", kind: .expense, sortOrder: 0)
        let buy = Entry(kind: .expense, amount: 8000, date: day(2026, 11, 1), accountID: card.id, categoryID: shopping.id)
        let refund = Entry(kind: .expense, amount: 3000, date: day(2026, 11, 5), accountID: card.id, categoryID: shopping.id)
        refund.isRefund = true
        let ledger = Ledger(accounts: [card], categories: [shopping], entries: [buy, refund])
        let month = Ledger.monthInterval(containing: day(2026, 11, 1))

        XCTAssertEqual(ledger.spendingByCategory(in: month)[shopping.id], 5000)
        XCTAssertEqual(ledger.balance(of: card), -5000)
    }
}

@MainActor
final class BillingTests: XCTestCase {
    private func rakuten() -> Account {
        let card = Account(name: "Rakuten Card", kind: .credit)
        card.closingDay = 31
        card.paymentDay = 27
        card.createdAt = day(2026, 10, 1)
        return card
    }

    func testCycleDatesClampToMonthLength() {
        let february = Billing.cycle(year: 2026, month: 2, closingDay: 31, paymentDay: 27)
        XCTAssertEqual(february.closingBoundary, day(2026, 3, 1, hour: 0))
        XCTAssertEqual(february.paymentDate, day(2026, 3, 27, hour: 0))

        let december = Billing.cycle(year: 2026, month: 12, closingDay: 15, paymentDay: 10)
        XCTAssertEqual(december.paymentDate, day(2027, 1, 10, hour: 0))
    }

    func testDueAndNextBill() {
        let card = rakuten()
        let october = Entry(kind: .expense, amount: 3000, date: day(2026, 10, 10), accountID: card.id)
        let november = Entry(kind: .expense, amount: 1000, date: day(2026, 11, 2), accountID: card.id)
        let ledger = Ledger(accounts: [card], entries: [october, november])

        let status = Billing.status(for: card, ledger: ledger, now: day(2026, 11, 5))
        XCTAssertEqual(status.due, 3000)
        XCTAssertEqual(status.dueDate, day(2026, 11, 27, hour: 0))
        XCTAssertEqual(status.nextSoFar, 1000)
        XCTAssertFalse(status.isOverdue)
    }

    func testOpeningUnpaidCountsTowardNextDue() {
        let card = rakuten()
        card.createdAt = day(2026, 11, 5)
        card.openingBalance = -12_000
        let status = Billing.status(for: card, ledger: Ledger(accounts: [card], entries: []), now: day(2026, 11, 6))
        XCTAssertEqual(status.due, 12_000)
    }

    func testAutoPayoffCreatedOnceAndClearsDue() throws {
        let container = try ModelContainer(for: Account.self, BudgetCategory.self, Entry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "BillingTests-\(UUID().uuidString)")!
        let bank = Account(name: "SMBC bank", kind: .bank, openingBalance: 50_000)
        let card = rakuten()
        card.payFromAccountID = bank.id
        let purchase = Entry(kind: .expense, amount: 3000, date: day(2026, 10, 10), accountID: card.id)
        context.insert(bank)
        context.insert(card)
        context.insert(purchase)

        let now = day(2026, 11, 28)
        let created = Billing.runAutoPayoffs(context: context, accounts: [bank, card], entries: [purchase], now: now, defaults: defaults)
        XCTAssertEqual(created, 1)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        let payoff = try XCTUnwrap(entries.first { $0.kind == .payoff })
        XCTAssertEqual(payoff.amount, 3000)
        XCTAssertFalse(payoff.isConfirmed)

        let ledger = Ledger(accounts: [bank, card], entries: entries)
        XCTAssertEqual(Billing.status(for: card, ledger: ledger, now: now).due, 0)
        XCTAssertEqual(ledger.balance(of: bank), 47_000)

        let again = Billing.runAutoPayoffs(context: context, accounts: [bank, card], entries: entries, now: now, defaults: defaults)
        XCTAssertEqual(again, 0)
    }

    func testReminderShowsShortfall() {
        let bank = Account(name: "SMBC bank", kind: .bank, openingBalance: 1000)
        let card = rakuten()
        card.payFromAccountID = bank.id
        let purchase = Entry(kind: .expense, amount: 3000, date: day(2026, 10, 10), accountID: card.id)
        let ledger = Ledger(accounts: [bank, card], entries: [purchase])

        let reminders = Billing.reminders(ledger: ledger, now: day(2026, 11, 22))
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.shortfall, 2000)
        XCTAssertTrue(Billing.reminders(ledger: ledger, now: day(2026, 11, 5)).isEmpty, "Outside the 7-day window")
    }
}

@MainActor
final class QuickLogTests: XCTestCase {
    func testMatchesCardAndRemembersMerchantCategory() {
        let olive = Account(name: "SMBC Olive credit", kind: .credit)
        olive.walletCardName = "Olive"
        let rakuten = Account(name: "Rakuten Card", kind: .credit)
        XCTAssertEqual(QuickLog.matchAccount(card: "Olive フレキシブルペイ", accounts: [olive, rakuten])?.id, olive.id)
        XCTAssertEqual(QuickLog.matchAccount(card: "rakuten card", accounts: [olive, rakuten])?.id, rakuten.id)

        let konbini = BudgetCategory(name: "Konbini", emoji: "🏪", kind: .expense, sortOrder: 0)
        let other = BudgetCategory(name: "Other", emoji: "📦", kind: .expense, sortOrder: 1)
        let past = Entry(kind: .expense, amount: 500, date: day(2026, 11, 1), categoryID: konbini.id)
        past.merchant = "Lawson"
        XCTAssertEqual(QuickLog.guessCategory(merchant: "LAWSON", entries: [past], categories: [konbini, other]), konbini.id)
        XCTAssertEqual(QuickLog.guessCategory(merchant: "New shop", entries: [past], categories: [konbini, other]), other.id)
    }
}

final class InsightsTests: XCTestCase {
    func testCumulativeSpendingRunsByDay() {
        let bank = Account(name: "Bank", kind: .bank)
        let food = BudgetCategory(name: "Restaurants", emoji: "🍜", kind: .expense, sortOrder: 0)
        let a = Entry(kind: .expense, amount: 1000, date: day(2026, 11, 1), accountID: bank.id, categoryID: food.id)
        let b = Entry(kind: .expense, amount: 500, date: day(2026, 11, 3), accountID: bank.id, categoryID: food.id)
        let late = Entry(kind: .expense, amount: 9000, date: day(2026, 11, 20), accountID: bank.id, categoryID: food.id)
        let ledger = Ledger(accounts: [bank], categories: [food], entries: [a, b, late])
        let month = Ledger.monthInterval(containing: day(2026, 11, 1))

        XCTAssertEqual(ledger.cumulativeSpending(in: month, until: day(2026, 11, 4, hour: 0)), [1000, 1000, 1500])
        XCTAssertEqual(ledger.cumulativeSpending(in: month).count, 30)
        XCTAssertEqual(ledger.cumulativeSpending(in: month).last, 10_500)
    }

    func testMonthSummaryPerDayAllowance() {
        let bank = Account(name: "Bank", kind: .bank)
        let food = BudgetCategory(name: "Supermarket", emoji: "🛒", kind: .expense, sortOrder: 0, monthlyBudget: 40_000)
        let shop = Entry(kind: .expense, amount: 10_000, date: day(2026, 11, 2), accountID: bank.id, categoryID: food.id)
        let ledger = Ledger(accounts: [bank], categories: [food], entries: [shop])
        let summary = MonthSummary(ledger: ledger, month: day(2026, 11, 11), now: day(2026, 11, 11))

        XCTAssertEqual(summary.spent, 10_000)
        XCTAssertEqual(summary.left, 30_000)
        XCTAssertEqual(summary.daysLeft, 20)
        XCTAssertEqual(summary.perDay, 1_500)
        XCTAssertEqual(summary.cumulative.count, 11)
        XCTAssertEqual(summary.previous.count, 31)
    }

    func testHomeSectionOrderKeepsKnownSectionsAndAddsNewOnes() {
        XCTAssertEqual(HomeSection.order(from: "budgets,bogus,recent,budgets"), [.budgets, .recent, .bills, .partner])
        XCTAssertEqual(HomeSection.hidden(from: "partner,nope"), [.partner])
        XCTAssertEqual(HomeSection.encode([.recent, .bills]), "recent,bills")
    }

    func testShortYenLabels() {
        XCTAssertEqual(Yen.short(200_000), "¥200k")
        XCTAssertEqual(Yen.short(950), "¥950")
    }
}
