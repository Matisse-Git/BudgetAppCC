import Foundation
import SwiftData

// All stored properties have defaults or are optional and nothing is marked unique,
// so CloudKit sync can be switched on later without a migration.
// Links between records use UUIDs instead of relationships to keep export/import simple.

enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case bank, topUp, cash, credit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bank: return "Bank"
        case .topUp: return "Top-up"
        case .cash: return "Cash"
        case .credit: return "Credit"
        }
    }

    var defaultEmoji: String {
        switch self {
        case .bank: return "🏦"
        case .topUp: return "📲"
        case .cash: return "💴"
        case .credit: return "💳"
        }
    }
}

/// Where a card payment goes when its day is a weekend or a Japanese bank holiday.
enum HolidayShift: String, Codable, CaseIterable, Identifiable {
    case nextBusinessDay = "next"
    case previousBusinessDay = "previous"
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nextBusinessDay: return "Next business day"
        case .previousBusinessDay: return "Previous business day"
        case .none: return "Keep the date"
        }
    }
}

/// When a card's statement closes and when it's paid.
struct BillingRule: Equatable {
    /// 1–31; 31 means the last day of the month.
    var closingDay = 31
    /// 1–31; 31 means the last day of the month.
    var paymentDay = 27
    /// 0 = same month as closing, 1 = next month, 2 = month after next.
    var paymentMonthOffset = 1
    var shift: HolidayShift = .nextBusinessDay
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case expense, income

    var id: String { rawValue }
    var label: String { self == .expense ? "Expenses" : "Income" }
}

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    /// Money spent. `partnerShare` of it is owed back and is not my spending.
    case expense
    case income
    /// Between two of my own accounts (e.g. SMBC → Revolut top-up). Not spending.
    case transfer
    /// Paying off a credit account (bank → card). Not spending.
    case payoff
    /// Partner repaying me. Not income.
    case settlement
    /// Manual balance correction. Signed amount. Not spending.
    case adjust

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        case .payoff: return "Card payoff"
        case .settlement: return "Repayment"
        case .adjust: return "Balance adjustment"
        }
    }
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🏦"
    var kindRaw: String = AccountKind.bank.rawValue
    /// Value when the account was added. Credit accounts store the unpaid amount as a negative number.
    var openingBalance: Int = 0
    var createdAt: Date = Date()
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var currencyCode: String = "JPY"

    // Credit accounts
    /// Day of month the statement closes (締め日). 31 = end of month.
    var closingDay: Int = 31
    /// Day of the month the bill is paid (支払日), `paymentMonthOffset` months after closing.
    var paymentDay: Int = 27
    var payFromAccountID: UUID? = nil
    var autoPayoff: Bool = true
    /// Months between closing and payment: 0 = same month, 1 = next month (the usual), 2 = month after next.
    var paymentMonthOffset: Int = 1
    /// What happens when the payment day isn't a business day (`HolidayShift`).
    var holidayShiftRaw: String = HolidayShift.nextBusinessDay.rawValue
    /// Credit limit in yen. 0 means not set.
    var creditLimit: Int = 0
    /// Alert when what's owed reaches this percentage of the limit. 0 means off.
    var limitAlertPercent: Int = 0
    /// Installment fee (分割手数料) as an annual percentage, e.g. 15.0. 0 means no fee.
    var installmentFeeRate: Double = 0
    /// Remind 3 days and 1 day before each payment.
    var paymentReminder: Bool = true
    /// Warn when the paying account won't cover a bill on its due date.
    var shortfallWarning: Bool = true

    /// Card face colour (`CardColor`) or account hue (`Hue`). Empty picks a lasting default.
    var colorKey: String = ""

    // Top-up accounts
    /// When true, topping up counts as spending (e.g. PASMO → Transport) and no balance is tracked.
    var countsTopUpAsSpending: Bool = false
    var topUpCategoryID: UUID? = nil

    /// Name of the card in Apple Wallet, for matching automation input.
    var walletCardName: String = ""
    /// Reserved for sharing a single account later. Nil means private.
    var shareScope: String? = nil

    init(name: String, kind: AccountKind, emoji: String? = nil, openingBalance: Int = 0, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.emoji = emoji ?? kind.defaultEmoji
        self.openingBalance = openingBalance
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .bank }
        set { kindRaw = newValue.rawValue }
    }

    /// False for top-up accounts whose top-ups count as spending (PASMO).
    var tracksBalance: Bool { !(kind == .topUp && countsTopUpAsSpending) }

    /// Accounts that can pay a card bill or receive money.
    var holdsMoney: Bool { kind != .credit && tracksBalance }

    var holidayShift: HolidayShift {
        get { HolidayShift(rawValue: holidayShiftRaw) ?? .nextBusinessDay }
        set { holidayShiftRaw = newValue.rawValue }
    }

    /// Closing and payment rules of a credit account.
    var billingRule: BillingRule {
        BillingRule(closingDay: closingDay, paymentDay: paymentDay,
                    paymentMonthOffset: paymentMonthOffset, shift: holidayShift)
    }

    var displayName: String { "\(emoji) \(name)" }
}

@Model
final class BudgetCategory {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "📦"
    var kindRaw: String = CategoryKind.expense.rawValue
    /// Monthly budget in yen. 0 means no budget.
    var monthlyBudget: Int = 0
    var sortOrder: Int = 0
    var isArchived: Bool = false

    init(name: String, emoji: String, kind: CategoryKind, sortOrder: Int, monthlyBudget: Int = 0) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder
        self.monthlyBudget = monthlyBudget
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var displayName: String { "\(emoji) \(name)" }
}

@Model
final class Entry {
    var id: UUID = UUID()
    var kindRaw: String = EntryKind.expense.rawValue
    /// Whole yen. Positive, except for `.adjust` where it is the signed change.
    var amount: Int = 0
    var date: Date = Date()
    var note: String = ""
    var merchant: String = ""
    /// Expense: paid from. Income/settlement: received in. Transfer/payoff: from. Adjust: the account.
    var accountID: UUID? = nil
    /// Transfer/payoff: destination.
    var toAccountID: UUID? = nil
    var categoryID: UUID? = nil
    /// Expense that gives money back; reduces spending in its category.
    var isRefund: Bool = false
    /// Part of an expense owed back by my partner. Not my spending.
    var partnerShare: Int = 0
    /// Settlement for one specific shared expense ("mark repaid").
    var settlementTargetID: UUID? = nil
    /// Card payoffs: ticked once I've seen the real debit.
    var isConfirmed: Bool = true
    var isAutoCreated: Bool = false
    /// Logged by Shortcuts/automation; worth a glance.
    var needsReview: Bool = false
    /// Credit bill cycle this payoff belongs to.
    var billCycleKey: String? = nil
    var currencyCode: String = "JPY"
    var createdAt: Date = Date()

    // Card installments (分割払い). Only for non-refund expenses on a credit card.
    /// Number of monthly installments; 0 or 1 means paid in one go.
    var installmentCount: Int = 0
    /// How the purchase counts as spending (`InstallmentMode`).
    var installmentModeRaw: String = InstallmentMode.monthly.rawValue
    /// Exact total fee for this purchase; -1 uses the card's rate.
    var installmentFeeOverride: Int = -1
    /// Set by "Pay off the rest": installments not yet billed move to the bill open on this date.
    var installmentPaidOffAt: Date? = nil
    /// The quick entry this was logged from, for the widget's "today ×N" count.
    var quickEntryID: UUID? = nil

    init(kind: EntryKind, amount: Int, date: Date = Date(), accountID: UUID? = nil, toAccountID: UUID? = nil, categoryID: UUID? = nil) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.date = date
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.categoryID = categoryID
        self.createdAt = Date()
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// My part of an expense.
    var myShare: Int { amount - partnerShare }

    var isSharedExpense: Bool { kind == .expense && !isRefund && partnerShare > 0 }

    /// A purchase paid in two or more card installments.
    var isInstallment: Bool { kind == .expense && !isRefund && installmentCount >= 2 }

    var installmentMode: InstallmentMode {
        get { InstallmentMode(rawValue: installmentModeRaw) ?? .monthly }
        set { installmentModeRaw = newValue.rawValue }
    }
}

/// How an installment purchase counts as spending.
enum InstallmentMode: String, Codable, CaseIterable, Identifiable {
    /// The full amount in the month it was bought.
    case all
    /// Each installment in the month it's paid.
    case monthly
    /// Never budget spending; it only lowers net worth while it's owed.
    case debt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All now"
        case .monthly: return "Monthly"
        case .debt: return "Debt only"
        }
    }

    var detail: String {
        switch self {
        case .all: return "The full price counts as spending this month."
        case .monthly: return "Each installment counts in the month it's paid."
        case .debt: return "Never counts toward budgets; only lowers net worth until it's paid."
        }
    }
}

/// A purchase that's always the same (daily breakfast), logged in one tap from the add screen,
/// the Quick entries widget or Shortcuts. Expenses only.
@Model
final class QuickEntry {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "⭐️"
    var amount: Int = 0
    var categoryID: UUID? = nil
    /// Nil means "use the default account".
    var accountID: UUID? = nil
    var merchant: String = ""
    /// Part of the amount owed back by my partner.
    var partnerShare: Int = 0
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(name: String, emoji: String, amount: Int, categoryID: UUID?, accountID: UUID? = nil,
         merchant: String = "", partnerShare: Int = 0, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.amount = amount
        self.categoryID = categoryID
        self.accountID = accountID
        self.merchant = merchant
        self.partnerShare = partnerShare
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var displayName: String { "\(emoji) \(name)" }

    /// The copy the widget and pending taps carry.
    var card: QuickEntryCard {
        QuickEntryCard(id: id, name: name, emoji: emoji, amount: amount, categoryID: categoryID,
                       accountID: accountID, merchant: merchant, partnerShare: partnerShare)
    }
}
