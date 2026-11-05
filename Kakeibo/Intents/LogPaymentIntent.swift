import AppIntents
import Foundation
import SwiftData

/// Matching helpers for entries logged from Shortcuts / Wallet automations.
enum QuickLog {
    static func matchAccount(card: String?, accounts: [Account]) -> Account? {
        let name = (card ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let candidates = accounts.filter { !$0.isArchived }
        if let match = candidates.first(where: { !$0.walletCardName.isEmpty && name.contains($0.walletCardName.lowercased()) }) {
            return match
        }
        return candidates.first(where: { name.contains($0.name.lowercased()) || $0.name.lowercased().contains(name) })
    }

    /// Category used last time at this merchant, else "Other".
    static func guessCategory(merchant: String, entries: [Entry], categories: [BudgetCategory]) -> UUID? {
        let key = merchant.lowercased()
        if !key.isEmpty,
           let previous = entries
            .filter({ $0.kind == .expense && $0.merchant.lowercased() == key && $0.categoryID != nil })
            .max(by: { $0.date < $1.date }) {
            return previous.categoryID
        }
        let expenseCategories = categories.filter { $0.kind == .expense && !$0.isArchived }
        return expenseCategories.first(where: { $0.name == "Other" })?.id ?? expenseCategories.last?.id
    }
}

/// Records an expense without opening the app. Built for a Wallet "Transaction" automation:
/// pass the automation's Amount, Merchant and Card. Entries are flagged for review.
struct LogPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Payment"
    static let description = IntentDescription("Adds an expense to Kakeibo, for example from a Wallet transaction automation. The entry is marked for review.")

    @Parameter(title: "Amount")
    var amount: String?

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Card")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant) paid with \(\.$card)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppData.shared.container.mainContext
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []

        let value = abs(amount.flatMap { Yen.parse($0) } ?? 0)
        let merchantName = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultID = UserDefaults.standard.string(forKey: SettingsKey.defaultAccountID).flatMap(UUID.init(uuidString:))
        let accountID = QuickLog.matchAccount(card: card, accounts: accounts)?.id ?? defaultID

        let entry = Entry(kind: .expense, amount: value, accountID: accountID,
                          categoryID: QuickLog.guessCategory(merchant: merchantName, entries: entries, categories: categories))
        entry.merchant = merchantName
        entry.needsReview = true
        entry.isAutoCreated = true
        if value == 0 { entry.note = "Amount missing" }
        context.insert(entry)
        context.saveAndRefresh()

        let place = merchantName.isEmpty ? "" : " at \(merchantName)"
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(Yen.format(value))\(place)."))
    }
}

struct KakeiboShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAddEntryIntent(),
            phrases: ["Add an entry in \(.applicationName)", "Log spending in \(.applicationName)"],
            shortTitle: "Add entry",
            systemImageName: "yensign.circle"
        )
        AppShortcut(
            intent: LogPaymentIntent(),
            phrases: ["Log a payment in \(.applicationName)"],
            shortTitle: "Log payment",
            systemImageName: "creditcard"
        )
    }
}
