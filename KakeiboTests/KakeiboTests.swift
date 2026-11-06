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

        // Jan 10, 2027 is a Sunday and Jan 11 is Coming of Age Day, so the money leaves on Tuesday the 12th.
        let december = Billing.cycle(year: 2026, month: 12, closingDay: 15, paymentDay: 10)
        XCTAssertEqual(december.nominalPaymentDate, day(2027, 1, 10, hour: 0))
        XCTAssertEqual(december.paymentDate, day(2027, 1, 12, hour: 0))
        XCTAssertEqual(december.start, day(2026, 11, 16, hour: 0))
        XCTAssertEqual(december.closingDate, day(2026, 12, 15, hour: 0))
    }

    // The canvas's own examples (Card bills sticky note, CreditCard and CardSetup artboards).
    func testPaymentsMoveOffWeekendsAndBankHolidays() {
        let everyday = BillingRule(closingDay: 31, paymentDay: 27)
        let november = Billing.cycle(year: 2026, month: 11, rule: everyday)
        XCTAssertEqual(november.nominalPaymentDate, day(2026, 12, 27, hour: 0), "Sunday")
        XCTAssertEqual(november.paymentDate, day(2026, 12, 28, hour: 0))
        XCTAssertEqual(Billing.shiftCause(of: november), .weekend(weekday: day(2026, 12, 27).formatted(.dateTime.weekday(.wide))))

        let store = BillingRule(closingDay: 10, paymentDay: 2)
        let storeNovember = Billing.cycle(year: 2026, month: 11, rule: store)
        XCTAssertEqual(storeNovember.start, day(2026, 10, 11, hour: 0))
        XCTAssertEqual(storeNovember.paymentDate, day(2026, 12, 2, hour: 0))
        XCTAssertFalse(storeNovember.isShifted)
        // Sat Jan 2 → Jan 3 is a Sunday and both are bank holidays → Mon Jan 4.
        let storeDecember = Billing.cycle(year: 2026, month: 12, rule: store)
        XCTAssertEqual(storeDecember.paymentDate, day(2027, 1, 4, hour: 0))

        var earlier = everyday
        earlier.shift = .previousBusinessDay
        XCTAssertEqual(Billing.cycle(year: 2026, month: 11, rule: earlier).paymentDate, day(2026, 12, 25, hour: 0))
        var fixed = everyday
        fixed.shift = .none
        XCTAssertEqual(Billing.cycle(year: 2026, month: 11, rule: fixed).paymentDate, day(2026, 12, 27, hour: 0))
    }

    func testPaymentMonthOffset() {
        let sameMonth = BillingRule(closingDay: 5, paymentDay: 27, paymentMonthOffset: 0)
        XCTAssertEqual(Billing.cycle(year: 2026, month: 11, rule: sameMonth).paymentDate, day(2026, 11, 27, hour: 0))
        let monthAfterNext = BillingRule(closingDay: 15, paymentDay: 10, paymentMonthOffset: 2)
        XCTAssertEqual(Billing.cycle(year: 2026, month: 10, rule: monthAfterNext).paymentDate, day(2026, 12, 10, hour: 0))
        // A same-month payment day before closing can only mean next month.
        let impossible = BillingRule(closingDay: 20, paymentDay: 10, paymentMonthOffset: 0)
        XCTAssertEqual(Billing.cycle(year: 2026, month: 11, rule: impossible).nominalPaymentDate, day(2026, 12, 10, hour: 0))
    }

    func testPurchaseBelongsToTheCycleItClosesIn() {
        let store = BillingRule(closingDay: 10, paymentDay: 2)
        let cycle = Billing.cycle(containing: day(2026, 11, 17), rule: store)
        XCTAssertEqual(cycle.closingDate, day(2026, 12, 10, hour: 0))
        XCTAssertEqual(cycle.paymentDate, day(2027, 1, 4, hour: 0))
        XCTAssertEqual(Billing.cycle(containing: day(2026, 11, 10, hour: 23), rule: store).closingDate, day(2026, 11, 10, hour: 0))
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
        // The warning appears as soon as the statement closes, not just in the last week.
        XCTAssertEqual(Billing.reminders(ledger: ledger, now: day(2026, 11, 2)).first?.shortfall, 2000)
        XCTAssertTrue(Billing.reminders(ledger: ledger, now: day(2026, 11, 5), windowDays: 7).isEmpty)
    }

    func testShortfallCountsScheduledIncomeAndEarlierBills() {
        let bank = Account(name: "Main Bank", kind: .bank, openingBalance: 30_000)
        let card = rakuten()
        card.payFromAccountID = bank.id
        let other = Account(name: "Store Card", kind: .credit)
        other.closingDay = 10
        other.paymentDay = 2
        other.payFromAccountID = bank.id
        let purchase = Entry(kind: .expense, amount: 50_000, date: day(2026, 10, 10), accountID: card.id)
        let storePurchase = Entry(kind: .expense, amount: 40_000, date: day(2026, 11, 5), accountID: other.id)
        let now = day(2026, 11, 18)

        let short = Billing.reminders(ledger: Ledger(accounts: [bank, card, other], entries: [purchase, storePurchase]), now: now)
        XCTAssertEqual(short.map(\.account.name), ["Rakuten Card", "Store Card"], "Soonest first")
        XCTAssertEqual(short.first?.shortfall, 20_000)
        XCTAssertEqual(short.last?.shortfall, 60_000, "Counts the earlier bill from the same account")

        // Salary dated the 25th lands before the 27th: the first bill is covered.
        let salary = Entry(kind: .income, amount: 100_000, date: day(2026, 11, 25), accountID: bank.id)
        let covered = Billing.reminders(ledger: Ledger(accounts: [bank, card, other], entries: [purchase, storePurchase, salary]), now: now)
        XCTAssertEqual(covered.first?.projectedBalance, 130_000)
        XCTAssertEqual(covered.first?.shortfall, 0)
        XCTAssertEqual(covered.last?.shortfall, 0)

        other.shortfallWarning = false
        let muted = Billing.reminders(ledger: Ledger(accounts: [bank, card, other], entries: [purchase, storePurchase]), now: now)
        XCTAssertEqual(muted.last?.shortfall, 0)
    }

    func testClosedStatementsForTheFeed() {
        let card = rakuten()
        let october = Entry(kind: .expense, amount: 3000, date: day(2026, 10, 10), accountID: card.id)
        let november = Entry(kind: .expense, amount: 1000, date: day(2026, 11, 2), accountID: card.id)
        let ledger = Ledger(accounts: [card], entries: [october, november])
        let events = Billing.closedStatements(ledger: ledger, from: day(2026, 9, 1), to: day(2026, 12, 5))
        XCTAssertEqual(events.map(\.amount), [4000, 3000], "Nov 30 then Oct 31; nothing owed at the end of September")
        XCTAssertEqual(events.first?.cycle.closingDate, day(2026, 11, 30, hour: 0))
    }

    func testReminderDatesAreThreeAndOneDayBefore() {
        let dates = Billing.reminderDates(dueDate: day(2026, 12, 2, hour: 0), now: day(2026, 11, 18))
        XCTAssertEqual(dates, [day(2026, 11, 29, hour: 9), day(2026, 12, 1, hour: 9)])
        XCTAssertEqual(Billing.reminderDates(dueDate: day(2026, 12, 2, hour: 0), now: day(2026, 11, 30)), [day(2026, 12, 1, hour: 9)])
    }
}

@MainActor
final class ShiftedPayoffTests: XCTestCase {
    func testAutoPayoffWaitsForTheShiftedPaymentDay() throws {
        let container = try ModelContainer(for: Account.self, BudgetCategory.self, Entry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "ShiftedPayoff-\(UUID().uuidString)")!
        let bank = Account(name: "Main Bank", kind: .bank, openingBalance: 100_000)
        let card = Account(name: "Everyday Card", kind: .credit)
        card.closingDay = 31
        card.paymentDay = 27
        card.payFromAccountID = bank.id
        card.createdAt = day(2026, 10, 1)
        let purchase = Entry(kind: .expense, amount: 8_000, date: day(2026, 11, 17), accountID: card.id)
        [bank, card].forEach { context.insert($0) }
        context.insert(purchase)

        // Dec 27 is a Sunday: nothing is recorded until Monday the 28th.
        XCTAssertEqual(Billing.runAutoPayoffs(context: context, accounts: [bank, card], entries: [purchase],
                                              now: day(2026, 12, 27, hour: 20), defaults: defaults), 0)
        XCTAssertEqual(Billing.runAutoPayoffs(context: context, accounts: [bank, card], entries: [purchase],
                                              now: day(2026, 12, 28, hour: 10), defaults: defaults), 1)
        let payoff = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first { $0.kind == .payoff })
        XCTAssertEqual(payoff.date, day(2026, 12, 28, hour: 9))
        XCTAssertTrue(payoff.isAutoCreated)
    }
}

final class HolidayTests: XCTestCase {
    func testJapaneseHolidays2026() {
        let holidays = JapaneseHolidays.holidays(in: 2026).map { "\($0.month)/\($0.day)" }
        XCTAssertEqual(holidays, [
            "1/1", "1/2", "1/3", "1/12", "2/11", "2/23", "3/20", "4/29", "5/3", "5/4", "5/5", "5/6",
            "7/20", "8/11", "9/21", "9/22", "9/23", "10/12", "11/3", "11/23", "12/31",
        ])
        XCTAssertEqual(JapaneseHolidays.name(of: day(2026, 5, 6)), "Substitute Holiday")
        XCTAssertEqual(JapaneseHolidays.name(of: day(2026, 9, 22)), "Citizens' Holiday")
        XCTAssertEqual(JapaneseHolidays.name(of: day(2026, 1, 2)), "Bank holiday")
    }

    func testBusinessDays() {
        XCTAssertFalse(JapaneseHolidays.isBusinessDay(day(2026, 11, 3)), "Culture Day")
        XCTAssertFalse(JapaneseHolidays.isBusinessDay(day(2026, 11, 21)), "Saturday")
        XCTAssertTrue(JapaneseHolidays.isBusinessDay(day(2026, 11, 18)))
        XCTAssertEqual(JapaneseHolidays.nextBusinessDay(onOrAfter: day(2026, 5, 2)), day(2026, 5, 7, hour: 0), "Golden Week")
        XCTAssertEqual(JapaneseHolidays.previousBusinessDay(onOrBefore: day(2027, 1, 3)), day(2026, 12, 30, hour: 0))
    }

    func testOrdinals() {
        XCTAssertEqual(Ordinal.day(1), "1st")
        XCTAssertEqual(Ordinal.day(2), "2nd")
        XCTAssertEqual(Ordinal.day(13), "13th")
        XCTAssertEqual(Ordinal.day(22), "22nd")
        XCTAssertEqual(Ordinal.day(31), "end of month")
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
        XCTAssertEqual(summary.daysLeft, 19, "Days after today, as on the canvas (day 18 of 30 leaves 12)")
        XCTAssertEqual(summary.perDay, 1_578)
        XCTAssertEqual(summary.cumulative.count, 11)
        XCTAssertEqual(summary.previous.count, 31)
    }

    func testShortYenLabels() {
        XCTAssertEqual(Yen.short(200_000), "¥200k")
        XCTAssertEqual(Yen.short(950), "¥950")
    }
}

final class PaceTests: XCTestCase {
    private func ledger() -> Ledger {
        let bank = Account(name: "Bank", kind: .bank)
        func category(_ name: String, _ budget: Int, _ order: Int) -> BudgetCategory {
            BudgetCategory(name: name, emoji: "", kind: .expense, sortOrder: order, monthlyBudget: budget)
        }
        let dining = category("Dining Out", 25_000, 0)
        let cafe = category("Café & Snacks", 8_000, 1)
        let transport = category("Transport", 12_000, 2)
        let rent = category("Rent", 82_000, 3)
        let groceries = category("Groceries", 42_000, 4)
        let utilities = category("Utilities", 0, 5)
        func spend(_ amount: Int, _ month: Int, _ d: Int, _ c: BudgetCategory) -> Entry {
            Entry(kind: .expense, amount: amount, date: day(2026, month, d), accountID: bank.id, categoryID: c.id)
        }
        let entries = [
            spend(26_800, 11, 17, dining), spend(6_920, 11, 10, cafe), spend(6_840, 11, 5, transport),
            spend(82_000, 11, 1, rent), spend(22_260, 11, 12, groceries), spend(9_840, 11, 6, utilities),
            spend(24_300, 10, 12, dining), spend(6_900, 10, 25, dining),
        ]
        return Ledger(accounts: [bank], categories: [dining, cafe, transport, rent, groceries, utilities], entries: entries)
    }

    func testCategoriesSortByAttention() {
        let pace = BudgetPace(ledger: ledger(), month: day(2026, 11, 18), now: day(2026, 11, 18))
        XCTAssertEqual(pace.daysElapsed, 18)
        XCTAssertEqual(pace.daysRemaining, 12)
        XCTAssertEqual(pace.needsAttention.map(\.category.name), ["Dining Out", "Café & Snacks"])
        XCTAssertEqual(pace.needsAttention.map(\.status), [.over, .atRisk])
        XCTAssertEqual(pace.needsAttention.last?.runsOutDay, 21, "¥6,920 of ¥8,000 by the 18th runs out around the 21st")
        XCTAssertEqual(pace.onTrack.map(\.category.name), ["Rent", "Transport", "Groceries"], "Rent is exactly used up, not at risk")
        XCTAssertEqual(pace.unbudgeted.map(\.category.name), ["Utilities"])
        XCTAssertEqual(pace.needsAttention.first?.vsPrevious, 2_500, "Like for like: only Oct 1–18 counts")
    }

    func testTotalsPaceAndComparison() {
        let pace = BudgetPace(ledger: ledger(), month: day(2026, 11, 18), now: day(2026, 11, 18))
        XCTAssertEqual(pace.budget, 169_000)
        XCTAssertEqual(pace.spent, 154_660)
        XCTAssertEqual(pace.pace, 101_400)
        XCTAssertEqual(pace.status, .atRisk)
        XCTAssertEqual(pace.perDay, 1_195)
        XCTAssertEqual(pace.previousSameDays, 24_300)
        XCTAssertEqual(pace.comparisonLabel(), "\(day(2026, 10, 1).formatted(.dateTime.month(.abbreviated))) 1–18")

        let october = BudgetPace(ledger: ledger(), month: day(2026, 10, 5), now: day(2026, 11, 18))
        XCTAssertFalse(october.isCurrentMonth)
        XCTAssertEqual(october.daysElapsed, 31)
        XCTAssertEqual(october.perDay, 0)
        XCTAssertEqual(october.spent, 31_200)
    }

    func testTrendsAverageProjectionAndKept() {
        let ledger = ledger()
        let salary = BudgetCategory(name: "Salary", emoji: "", kind: .income, sortOrder: 100)
        let bank = ledger.accounts[0]
        let pay = Entry(kind: .income, amount: 300_000, date: day(2026, 10, 25), accountID: bank.id, categoryID: salary.id)
        let withPay = Ledger(accounts: ledger.accounts, categories: ledger.categories + [salary], entries: ledger.entries + [pay])
        let trends = SpendingTrends(ledger: withPay, now: day(2026, 11, 18))
        XCTAssertEqual(trends.averageMonths, 1, "Only October had spending")
        XCTAssertEqual(trends.average.count, 31)
        XCTAssertEqual(trends.average.last, 31_200)
        XCTAssertEqual(trends.averageMonthly, 31_200)
        XCTAssertEqual(trends.projected, 154_660 * 30 / 18)
        XCTAssertEqual(trends.kept, 300_000 - 31_200)
        XCTAssertEqual(trends.categoryChanges.first?.category.name, "Dining Out", "Ascending: +¥2,500 is the smallest change")
        XCTAssertEqual(trends.categoryChanges.last?.category.name, "Rent")
    }

    func testCategoryPaceStatus() {
        let food = BudgetCategory(name: "Food", emoji: "", kind: .expense, sortOrder: 0, monthlyBudget: 30_000)
        XCTAssertEqual(BudgetPace.categoryPace(food, spent: 10_000, elapsed: 15, days: 30, previous: 0).status, .onTrack)
        XCTAssertEqual(BudgetPace.categoryPace(food, spent: 20_000, elapsed: 15, days: 30, previous: 0).status, .atRisk)
        XCTAssertEqual(BudgetPace.categoryPace(food, spent: 20_000, elapsed: 15, days: 30, previous: 0).runsOutDay, 23)
        XCTAssertEqual(BudgetPace.categoryPace(food, spent: 30_001, elapsed: 15, days: 30, previous: 0).status, .over)
        XCTAssertEqual(BudgetPace.categoryPace(food, spent: 30_000, elapsed: 2, days: 30, previous: 0).status, .onTrack)
    }
}

final class SuggestionTests: XCTestCase {
    func testPicksCategoryByTimeOfDayAndAccountByLastUse() {
        let wallet = Account(name: "Wallet", kind: .cash)
        let qr = Account(name: "QR Pay", kind: .topUp)
        let dining = BudgetCategory(name: "Dining Out", emoji: "", kind: .expense, sortOrder: 0)
        let cafe = BudgetCategory(name: "Café & Snacks", emoji: "", kind: .expense, sortOrder: 1)
        var entries: [Entry] = []
        // Weekday lunches out, morning coffees on QR Pay.
        for d in [2, 3, 4, 5, 9, 10, 11, 12] {
            entries.append(Entry(kind: .expense, amount: 980, date: day(2026, 11, d, hour: 12), accountID: wallet.id, categoryID: dining.id))
            let coffee = Entry(kind: .expense, amount: 150, date: day(2026, 11, d, hour: 8), accountID: qr.id, categoryID: cafe.id)
            entries.append(coffee)
        }
        let categories = [dining, cafe]
        let lunch = Calendar.kakeibo.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12, minute: 41))!
        let morning = Calendar.kakeibo.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 8, minute: 10))!
        XCTAssertEqual(Suggestions.category(kind: .expense, at: lunch, entries: entries, categories: categories), dining.id)
        XCTAssertEqual(Suggestions.category(kind: .expense, at: morning, entries: entries, categories: categories), cafe.id)
        XCTAssertNil(Suggestions.category(kind: .income, at: lunch, entries: entries, categories: categories))
        XCTAssertEqual(Suggestions.account(forCategory: cafe.id, kind: .expense, entries: entries, accounts: [wallet, qr]), qr.id)
    }

    func testTilesKeepTheUsersOrderAndIncludeTheSelection() {
        let names = ["Rent", "Utilities", "Phone", "Transport", "Supermarket", "Konbini", "Restaurants", "Shopping", "Subscriptions", "Other"]
        let categories = names.enumerated().map { BudgetCategory(name: $0.element, emoji: "", kind: .expense, sortOrder: $0.offset) }
        let used = ["Konbini", "Restaurants", "Supermarket", "Transport", "Shopping", "Other", "Subscriptions"]
        let entries = used.compactMap { name in
            categories.first { $0.name == name }.map { Entry(kind: .expense, amount: 500, date: day(2026, 11, 10), categoryID: $0.id) }
        }
        let tiles = Suggestions.tiles(kind: .expense, selected: nil, limit: 7, entries: entries, categories: categories, now: day(2026, 11, 18))
        XCTAssertEqual(tiles.map(\.name), ["Transport", "Supermarket", "Konbini", "Restaurants", "Shopping", "Subscriptions", "Other"])
        let rent = categories[0]
        let withRent = Suggestions.tiles(kind: .expense, selected: rent.id, limit: 7, entries: entries, categories: categories, now: day(2026, 11, 18))
        XCTAssertTrue(withRent.contains { $0.id == rent.id })
        XCTAssertEqual(withRent.count, 7)
    }
}

final class AccountInsightTests: XCTestCase {
    func testForecastListsScheduledIncomeAndBillsWithBalanceAfter() {
        let bank = Account(name: "Main Bank", kind: .bank, openingBalance: 184_630)
        let card = Account(name: "Everyday Card", kind: .credit)
        card.closingDay = 31
        card.paymentDay = 27
        card.payFromAccountID = bank.id
        let purchase = Entry(kind: .expense, amount: 86_420, date: day(2026, 10, 20), accountID: card.id)
        let salary = Entry(kind: .income, amount: 318_400, date: day(2026, 11, 25), accountID: bank.id)
        let ledger = Ledger(accounts: [bank, card], entries: [purchase, salary])

        let forecast = MoneyAccountForecast(account: bank, ledger: ledger, now: day(2026, 11, 18))
        XCTAssertEqual(forecast.today, 184_630, "Future-dated salary isn't in today's balance")
        XCTAssertEqual(forecast.upcoming.map(\.amount), [318_400, -86_420])
        XCTAssertEqual(forecast.upcoming.map(\.balanceAfter), [503_030, 416_610])
        XCTAssertNil(forecast.firstShortBill)
        XCTAssertEqual(forecast.past.count, 29)
        XCTAssertEqual(forecast.future.last?.balance, 416_610)
    }

    func testPastStatementsFindTheirPayment() {
        let bank = Account(name: "Main Bank", kind: .bank, openingBalance: 100_000)
        let card = Account(name: "Store Card", kind: .credit)
        card.closingDay = 10
        card.paymentDay = 2
        card.payFromAccountID = bank.id
        card.creditLimit = 300_000
        let september = Entry(kind: .expense, amount: 38_600, date: day(2026, 9, 20), accountID: card.id)
        let paid = Entry(kind: .payoff, amount: 38_600, date: day(2026, 11, 2, hour: 9), accountID: bank.id, toAccountID: card.id)
        paid.billCycleKey = Billing.cycle(year: 2026, month: 10, rule: card.billingRule).key(for: card.id)
        paid.isAutoCreated = true
        let october = Entry(kind: .expense, amount: 42_800, date: day(2026, 10, 20), accountID: card.id)
        let ledger = Ledger(accounts: [bank, card], entries: [september, paid, october])

        let statements = CardHistory.pastStatements(for: card, ledger: ledger, now: day(2026, 11, 18))
        XCTAssertEqual(statements.first?.amount, 38_600, "Sep 11 – Oct 10")
        XCTAssertEqual(statements.first?.payment?.id, paid.id)
        XCTAssertTrue(statements.first?.isPaid ?? false)
        XCTAssertEqual(card.available(ledger: ledger), 300_000 - 42_800)
    }
}

final class FeedbackLogicTests: XCTestCase {
    func testKeypadReportsKeysThatDoNothing() {
        XCTAssertEqual(KeypadView.apply("5", to: 12), 125)
        XCTAssertEqual(KeypadView.apply("⌫", to: 125), 12)
        XCTAssertEqual(KeypadView.apply("000", to: 3), 3_000)
        // These leave the amount unchanged, which is what triggers the "blocked" bump.
        XCTAssertEqual(KeypadView.apply("⌫", to: 0), 0)
        XCTAssertEqual(KeypadView.apply("0", to: 0), 0)
        XCTAssertEqual(KeypadView.apply("000", to: 0), 0)
        XCTAssertEqual(KeypadView.apply("000", to: 2_000_000), 2_000_000)
        XCTAssertEqual(KeypadView.apply("7", to: 100_000_000), 100_000_000)
        XCTAssertEqual(KeypadView.apply("00", to: 98), 9_800)
        XCTAssertEqual(KeypadView.apply("00", to: 0), 0)
        XCTAssertEqual(KeypadView.apply("00", to: 10_000_000), 10_000_000, "Stops at nine digits")
    }

    func testOverBudgetUsesMyShareAndTheEntrysMonth() {
        let bank = Account(name: "Bank", kind: .bank)
        let food = BudgetCategory(name: "Restaurants", emoji: "🍜", kind: .expense, sortOrder: 0, monthlyBudget: 10_000)
        let other = BudgetCategory(name: "Other", emoji: "📦", kind: .expense, sortOrder: 1)
        let early = Entry(kind: .expense, amount: 8_000, date: day(2026, 11, 2), accountID: bank.id, categoryID: food.id)
        let shared = Entry(kind: .expense, amount: 6_000, date: day(2026, 11, 9), accountID: bank.id, categoryID: food.id)
        shared.partnerShare = 3_000
        let lastMonth = Entry(kind: .expense, amount: 50_000, date: day(2026, 10, 20), accountID: bank.id, categoryID: food.id)
        let unbudgeted = Entry(kind: .expense, amount: 99_000, date: day(2026, 11, 3), accountID: bank.id, categoryID: other.id)

        let under = Ledger(accounts: [bank], categories: [food, other], entries: [early, lastMonth, unbudgeted])
        XCTAssertFalse(under.isOverBudget(categoryID: food.id, inMonthOf: day(2026, 11, 2)))
        XCTAssertTrue(under.isOverBudget(categoryID: food.id, inMonthOf: day(2026, 10, 20)))
        XCTAssertFalse(under.isOverBudget(categoryID: other.id, inMonthOf: day(2026, 11, 3)), "No budget is never over")

        // 8,000 + my 3,000 of the shared dinner = 11,000 > 10,000.
        let over = Ledger(accounts: [bank], categories: [food, other], entries: [early, shared])
        XCTAssertTrue(over.isOverBudget(categoryID: food.id, inMonthOf: day(2026, 11, 9)))

        let refund = Entry(kind: .expense, amount: 2_000, date: day(2026, 11, 10), accountID: bank.id, categoryID: food.id)
        refund.isRefund = true
        let backUnder = Ledger(accounts: [bank], categories: [food, other], entries: [early, shared, refund])
        XCTAssertFalse(backUnder.isOverBudget(categoryID: food.id, inMonthOf: day(2026, 11, 10)))
    }
}

final class BudgetListingTests: XCTestCase {
    func testOnlyBudgetedCategoriesAreListedUpFront() {
        let rent = BudgetCategory(name: "Rent", emoji: "🏠", kind: .expense, sortOrder: 0, monthlyBudget: 82_000)
        let konbini = BudgetCategory(name: "Konbini", emoji: "🏪", kind: .expense, sortOrder: 1)
        let food = BudgetCategory(name: "Supermarket", emoji: "🛒", kind: .expense, sortOrder: 2, monthlyBudget: 40_000)
        let other = BudgetCategory(name: "Other", emoji: "📦", kind: .expense, sortOrder: 3)
        let oldHobby = BudgetCategory(name: "Golf", emoji: "⛳️", kind: .expense, sortOrder: 4, monthlyBudget: 10_000)
        oldHobby.isArchived = true
        let quiet = BudgetCategory(name: "Gifts", emoji: "🎁", kind: .expense, sortOrder: 5)
        quiet.isArchived = true
        let salary = BudgetCategory(name: "Salary", emoji: "💴", kind: .income, sortOrder: 100)

        let spending: [UUID: Int] = [rent.id: 82_000, konbini.id: 1_200, oldHobby.id: 3_000, salary.id: 999]
        let listing = BudgetListing(categories: [rent, konbini, food, other, oldHobby, quiet, salary], spending: spending)

        XCTAssertEqual(listing.budgeted.map(\.name), ["Rent", "Supermarket"])
        XCTAssertEqual(listing.unbudgeted.map(\.name), ["Konbini", "Other", "Golf"],
                       "Archived categories only show when they have spending this month")
        XCTAssertEqual(listing.unbudgetedSpent, 4_200)
        XCTAssertFalse(listing.showsEverything)
    }

    func testNoBudgetsAtAllShowsEverything() {
        let a = BudgetCategory(name: "Rent", emoji: "🏠", kind: .expense, sortOrder: 0)
        let b = BudgetCategory(name: "Other", emoji: "📦", kind: .expense, sortOrder: 1)
        let listing = BudgetListing(categories: [a, b], spending: [b.id: 500])
        XCTAssertTrue(listing.showsEverything)
        XCTAssertEqual(listing.unbudgeted.count, 2)
        XCTAssertEqual(listing.unbudgetedSpent, 500)
    }
}

final class AccountLayoutTests: XCTestCase {
    private func make() -> [Account] {
        [
            Account(name: "SMBC bank", kind: .bank, sortOrder: 0),
            Account(name: "Olive", kind: .credit, sortOrder: 1),
            Account(name: "Revolut", kind: .topUp, sortOrder: 2),
            Account(name: "Cash", kind: .cash, sortOrder: 3),
            Account(name: "PayPay", kind: .topUp, sortOrder: 4),
            Account(name: "Rakuten", kind: .credit, sortOrder: 5),
        ]
    }

    private func names(_ groups: [AccountGroup]) -> [[String]] { groups.map { $0.accounts.map(\.name) } }

    func testFlatAndGroupedViewsShareOneOrder() {
        let all = make()
        XCTAssertEqual(AccountLayout.cards(all).map(\.name), ["Olive", "Rakuten"])
        XCTAssertEqual(names(AccountLayout.moneyGroups(all, byType: false)), [["SMBC bank", "Revolut", "Cash", "PayPay"]])
        XCTAssertEqual(AccountLayout.moneyGroups(all, byType: true).map(\.title), ["Bank", "Top-up", "Cash"])
        XCTAssertEqual(names(AccountLayout.moneyGroups(all, byType: true)), [["SMBC bank"], ["Revolut", "PayPay"], ["Cash"]])
    }

    func testMovingInTheFlatListRenumbersEverything() {
        let all = make()
        let groups = AccountLayout.editGroups(all, byType: false)
        // Drag Cash (index 2 of Money) to the top.
        AccountLayout.move(group: 1, from: IndexSet(integer: 2), to: 0, in: groups, all: all)
        XCTAssertEqual(names(AccountLayout.moneyGroups(all, byType: false)), [["Cash", "SMBC bank", "Revolut", "PayPay"]])
        XCTAssertEqual(AccountLayout.sorted(all).map(\.sortOrder), Array(0..<6), "Orders are unique and dense")
        XCTAssertEqual(AccountLayout.sorted(all).map(\.name).prefix(2), ["Olive", "Rakuten"], "Cards come first in pickers")
    }

    func testMovingInsideATypeCarriesOverToTheFlatList() {
        let all = make()
        let groups = AccountLayout.editGroups(all, byType: true)
        XCTAssertEqual(groups.map(\.id), ["cards", "bank", "topUp", "cash"])
        // Put PayPay above Revolut inside Top-up.
        AccountLayout.move(group: 2, from: IndexSet(integer: 1), to: 0, in: groups, all: all)
        XCTAssertEqual(names(AccountLayout.moneyGroups(all, byType: true)), [["SMBC bank"], ["PayPay", "Revolut"], ["Cash"]])
        XCTAssertEqual(names(AccountLayout.moneyGroups(all, byType: false)), [["SMBC bank", "PayPay", "Revolut", "Cash"]])
        // Reorder the cards.
        AccountLayout.move(group: 0, from: IndexSet(integer: 1), to: 0, in: AccountLayout.editGroups(all, byType: true), all: all)
        XCTAssertEqual(AccountLayout.cards(all).map(\.name), ["Rakuten", "Olive"])
    }

    func testArchivedAccountsStayAfterAndNewAccountsGoLast() {
        let all = make()
        let old = Account(name: "Old bank", kind: .bank, sortOrder: 0)
        old.isArchived = true
        let everything = all + [old]
        XCTAssertFalse(AccountLayout.moneyGroups(everything, byType: false)[0].accounts.contains { $0.name == "Old bank" })
        AccountLayout.move(group: 1, from: IndexSet(integer: 0), to: 2, in: AccountLayout.editGroups(everything, byType: false), all: everything)
        XCTAssertEqual(AccountLayout.sorted(everything).last?.name, "Old bank")
        XCTAssertEqual(AccountLayout.nextSortOrder(everything), 7)
        XCTAssertEqual(AccountLayout.nextSortOrder([]), 0)
    }

    func testTiesFallBackToCreationDate() {
        let first = Account(name: "First", kind: .cash, sortOrder: 0)
        first.createdAt = Date(timeIntervalSince1970: 100)
        let second = Account(name: "Second", kind: .cash, sortOrder: 0)
        second.createdAt = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(AccountLayout.sorted([second, first]).map(\.name), ["First", "Second"])
    }
}
