import Foundation
import SwiftData

/// Full JSON export/restore and a CSV of transactions.
enum Backup {
    struct File: Codable {
        var version: Int
        var exportedAt: Date
        var defaultAccountID: String?
        var partnerName: String?
        var accounts: [AccountRecord]
        var categories: [CategoryRecord]
        var entries: [EntryRecord]
        /// Missing in backups made before quick entries existed.
        var quickEntries: [QuickEntryRecord]?
    }

    struct AccountRecord: Codable {
        var id: UUID
        var name: String
        var emoji: String
        var kindRaw: String
        var openingBalance: Int
        var createdAt: Date
        var sortOrder: Int
        var isArchived: Bool
        var currencyCode: String
        var closingDay: Int
        var paymentDay: Int
        var payFromAccountID: UUID?
        var autoPayoff: Bool
        var countsTopUpAsSpending: Bool
        var topUpCategoryID: UUID?
        var walletCardName: String
        var shareScope: String?
        // Added with the canvas redesign; optional so older backups still restore.
        var paymentMonthOffset: Int?
        var holidayShiftRaw: String?
        var creditLimit: Int?
        var paymentReminder: Bool?
        var shortfallWarning: Bool?
        var colorKey: String?
        var limitAlertPercent: Int?
        var installmentFeeRate: Double?

        init(_ a: Account) {
            id = a.id; name = a.name; emoji = a.emoji; kindRaw = a.kindRaw; openingBalance = a.openingBalance
            createdAt = a.createdAt; sortOrder = a.sortOrder; isArchived = a.isArchived; currencyCode = a.currencyCode
            closingDay = a.closingDay; paymentDay = a.paymentDay; payFromAccountID = a.payFromAccountID
            autoPayoff = a.autoPayoff; countsTopUpAsSpending = a.countsTopUpAsSpending; topUpCategoryID = a.topUpCategoryID
            walletCardName = a.walletCardName; shareScope = a.shareScope
            paymentMonthOffset = a.paymentMonthOffset; holidayShiftRaw = a.holidayShiftRaw; creditLimit = a.creditLimit
            paymentReminder = a.paymentReminder; shortfallWarning = a.shortfallWarning; colorKey = a.colorKey
            limitAlertPercent = a.limitAlertPercent; installmentFeeRate = a.installmentFeeRate
        }

        func make() -> Account {
            let a = Account(name: name, kind: AccountKind(rawValue: kindRaw) ?? .bank, emoji: emoji, openingBalance: openingBalance, sortOrder: sortOrder)
            a.id = id; a.createdAt = createdAt; a.isArchived = isArchived; a.currencyCode = currencyCode
            a.closingDay = closingDay; a.paymentDay = paymentDay; a.payFromAccountID = payFromAccountID
            a.autoPayoff = autoPayoff; a.countsTopUpAsSpending = countsTopUpAsSpending; a.topUpCategoryID = topUpCategoryID
            a.walletCardName = walletCardName; a.shareScope = shareScope
            a.paymentMonthOffset = paymentMonthOffset ?? 1
            a.holidayShiftRaw = holidayShiftRaw ?? HolidayShift.nextBusinessDay.rawValue
            a.creditLimit = creditLimit ?? 0
            a.paymentReminder = paymentReminder ?? true
            a.shortfallWarning = shortfallWarning ?? true
            a.colorKey = colorKey ?? ""
            a.limitAlertPercent = limitAlertPercent ?? 0
            a.installmentFeeRate = installmentFeeRate ?? 0
            return a
        }
    }

    struct CategoryRecord: Codable {
        var id: UUID
        var name: String
        var emoji: String
        var kindRaw: String
        var monthlyBudget: Int
        var sortOrder: Int
        var isArchived: Bool

        init(_ c: BudgetCategory) {
            id = c.id; name = c.name; emoji = c.emoji; kindRaw = c.kindRaw
            monthlyBudget = c.monthlyBudget; sortOrder = c.sortOrder; isArchived = c.isArchived
        }

        func make() -> BudgetCategory {
            let c = BudgetCategory(name: name, emoji: emoji, kind: CategoryKind(rawValue: kindRaw) ?? .expense, sortOrder: sortOrder, monthlyBudget: monthlyBudget)
            c.id = id; c.isArchived = isArchived
            return c
        }
    }

    struct EntryRecord: Codable {
        var id: UUID
        var kindRaw: String
        var amount: Int
        var date: Date
        var note: String
        var merchant: String
        var accountID: UUID?
        var toAccountID: UUID?
        var categoryID: UUID?
        var isRefund: Bool
        var partnerShare: Int
        var settlementTargetID: UUID?
        var isConfirmed: Bool
        var isAutoCreated: Bool
        var needsReview: Bool
        var billCycleKey: String?
        var currencyCode: String
        var createdAt: Date
        // Added with card installments; optional so older backups still restore.
        var installmentCount: Int?
        var installmentModeRaw: String?
        var installmentFeeOverride: Int?
        var installmentPaidOffAt: Date?
        // Added with quick entries.
        var quickEntryID: UUID?

        init(_ e: Entry) {
            id = e.id; kindRaw = e.kindRaw; amount = e.amount; date = e.date; note = e.note; merchant = e.merchant
            accountID = e.accountID; toAccountID = e.toAccountID; categoryID = e.categoryID; isRefund = e.isRefund
            partnerShare = e.partnerShare; settlementTargetID = e.settlementTargetID; isConfirmed = e.isConfirmed
            isAutoCreated = e.isAutoCreated; needsReview = e.needsReview; billCycleKey = e.billCycleKey
            currencyCode = e.currencyCode; createdAt = e.createdAt
            installmentCount = e.installmentCount; installmentModeRaw = e.installmentModeRaw
            installmentFeeOverride = e.installmentFeeOverride; installmentPaidOffAt = e.installmentPaidOffAt
            quickEntryID = e.quickEntryID
        }

        func make() -> Entry {
            let e = Entry(kind: EntryKind(rawValue: kindRaw) ?? .expense, amount: amount, date: date,
                          accountID: accountID, toAccountID: toAccountID, categoryID: categoryID)
            e.id = id; e.note = note; e.merchant = merchant; e.isRefund = isRefund; e.partnerShare = partnerShare
            e.settlementTargetID = settlementTargetID; e.isConfirmed = isConfirmed; e.isAutoCreated = isAutoCreated
            e.needsReview = needsReview; e.billCycleKey = billCycleKey; e.currencyCode = currencyCode; e.createdAt = createdAt
            e.installmentCount = installmentCount ?? 0
            e.installmentModeRaw = installmentModeRaw ?? InstallmentMode.monthly.rawValue
            e.installmentFeeOverride = installmentFeeOverride ?? -1
            e.installmentPaidOffAt = installmentPaidOffAt
            e.quickEntryID = quickEntryID
            return e
        }
    }

    struct QuickEntryRecord: Codable {
        var id: UUID
        var name: String
        var emoji: String
        var amount: Int
        var categoryID: UUID?
        var accountID: UUID?
        var merchant: String
        var partnerShare: Int
        var sortOrder: Int
        var createdAt: Date

        init(_ q: QuickEntry) {
            id = q.id; name = q.name; emoji = q.emoji; amount = q.amount; categoryID = q.categoryID
            accountID = q.accountID; merchant = q.merchant; partnerShare = q.partnerShare
            sortOrder = q.sortOrder; createdAt = q.createdAt
        }

        func make() -> QuickEntry {
            let q = QuickEntry(name: name, emoji: emoji, amount: amount, categoryID: categoryID, accountID: accountID,
                               merchant: merchant, partnerShare: partnerShare, sortOrder: sortOrder)
            q.id = id; q.createdAt = createdAt
            return q
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var stamp: String {
        Date().formatted(.iso8601.year().month().day())
    }

    @MainActor
    static func exportData(context: ModelContext, defaults: UserDefaults = .standard) throws -> Data {
        let file = File(
            version: 2,
            exportedAt: Date(),
            defaultAccountID: defaults.string(forKey: SettingsKey.defaultAccountID),
            partnerName: defaults.string(forKey: SettingsKey.partnerName),
            accounts: try context.fetch(FetchDescriptor<Account>()).map { AccountRecord($0) },
            categories: try context.fetch(FetchDescriptor<BudgetCategory>()).map { CategoryRecord($0) },
            entries: try context.fetch(FetchDescriptor<Entry>()).map { EntryRecord($0) },
            quickEntries: try context.fetch(FetchDescriptor<QuickEntry>()).map { QuickEntryRecord($0) }
        )
        return try encoder.encode(file)
    }

    @MainActor
    static func exportJSON(context: ModelContext) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Kakeibo-backup-\(stamp).json")
        try exportData(context: context).write(to: url, options: .atomic)
        return url
    }

    /// Replaces all data with the backup.
    @MainActor
    static func restore(from data: Data, into context: ModelContext, defaults: UserDefaults = .standard) throws {
        let file = try decoder.decode(File.self, from: data)
        try context.delete(model: Entry.self)
        try context.delete(model: Account.self)
        try context.delete(model: BudgetCategory.self)
        file.accounts.forEach { context.insert($0.make()) }
        file.categories.forEach { context.insert($0.make()) }
        file.entries.forEach { context.insert($0.make()) }
        // A backup from before quick entries existed leaves the current ones alone.
        if let quickEntries = file.quickEntries {
            try context.delete(model: QuickEntry.self)
            quickEntries.forEach { context.insert($0.make()) }
        }
        try context.save()
        if let id = file.defaultAccountID { defaults.set(id, forKey: SettingsKey.defaultAccountID) }
        if let name = file.partnerName { defaults.set(name, forKey: SettingsKey.partnerName) }
        defaults.set(true, forKey: SettingsKey.seeded)
        defaults.set(true, forKey: SettingsKey.setupDone)
    }

    @MainActor
    static func exportCSV(context: ModelContext) throws -> URL {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let categories = try context.fetch(FetchDescriptor<BudgetCategory>())
        let entries = try context.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.date)]))
        let lookup = Lookup(accounts: accounts, categories: categories)

        var lines = ["date,type,amount,my_share,partner_share,refund,account,to_account,category,merchant,note,confirmed,installments"]
        for e in entries {
            let fields: [String] = [
                e.date.formatted(.iso8601.year().month().day()),
                e.kind.label,
                String(e.amount),
                String(e.kind == .expense ? (e.isRefund ? -e.amount : e.myShare) : 0),
                String(e.partnerShare),
                e.isRefund ? "yes" : "",
                e.accountID == nil ? "" : lookup.accountName(e.accountID),
                e.toAccountID == nil ? "" : lookup.accountName(e.toAccountID),
                lookup.category(e.categoryID)?.name ?? "",
                e.merchant,
                e.note,
                e.kind == .payoff ? (e.isConfirmed ? "yes" : "no") : "",
                e.isInstallment ? String(e.installmentCount) : "",
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "Kakeibo-transactions-\(stamp).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
