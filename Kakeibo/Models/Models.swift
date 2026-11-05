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
    /// Day of the following month the bill is paid (支払日).
    var paymentDay: Int = 27
    var payFromAccountID: UUID? = nil
    var autoPayoff: Bool = true

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
}
