import Foundation
import SwiftData

enum Seed {
    /// Inserts the starting categories and accounts. Returns the suggested default account.
    @MainActor
    @discardableResult
    static func insertDefaults(into context: ModelContext) -> UUID? {
        let expenses: [(String, String)] = [
            ("Rent", "🏠"), ("Utilities", "💡"), ("Phone", "📱"), ("Transport", "🚃"),
            ("Supermarket", "🛒"), ("Konbini", "🏪"), ("Restaurants", "🍜"), ("Shopping", "🛍️"),
            ("Subscriptions", "🔁"), ("Other", "📦"),
        ]
        var transportID: UUID?
        for (index, item) in expenses.enumerated() {
            let category = BudgetCategory(name: item.0, emoji: item.1, kind: .expense, sortOrder: index)
            context.insert(category)
            if item.0 == "Transport" { transportID = category.id }
        }
        let incomes: [(String, String)] = [("Salary", "💴"), ("Dad (iPhone share)", "🎁")]
        for (index, item) in incomes.enumerated() {
            context.insert(BudgetCategory(name: item.0, emoji: item.1, kind: .income, sortOrder: 100 + index))
        }

        let smbcBank = Account(name: "SMBC bank", kind: .bank, sortOrder: 0)
        let olive = Account(name: "SMBC Olive credit", kind: .credit, sortOrder: 1)
        olive.closingDay = 31
        olive.paymentDay = 26
        olive.payFromAccountID = smbcBank.id
        olive.colorKey = CardColor.teal.rawValue
        let rakuten = Account(name: "Rakuten Card", kind: .credit, sortOrder: 2)
        rakuten.closingDay = 31
        rakuten.paymentDay = 27
        rakuten.payFromAccountID = smbcBank.id
        rakuten.colorKey = CardColor.raspberry.rawValue
        let paidy = Account(name: "Paidy", kind: .credit, emoji: "🅿️", sortOrder: 3)
        paidy.closingDay = 31
        paidy.paymentDay = 27
        paidy.colorKey = CardColor.violet.rawValue
        let revolut = Account(name: "Revolut", kind: .topUp, emoji: "🌍", sortOrder: 4)
        let paypay = Account(name: "PayPay", kind: .topUp, emoji: "📲", sortOrder: 5)
        let pasmo = Account(name: "PASMO", kind: .topUp, emoji: "🚃", sortOrder: 6)
        pasmo.countsTopUpAsSpending = true
        pasmo.topUpCategoryID = transportID
        let cash = Account(name: "Cash", kind: .cash, sortOrder: 7)

        for account in [smbcBank, olive, rakuten, paidy, revolut, paypay, pasmo, cash] {
            context.insert(account)
        }
        try? context.save()
        return olive.id
    }
}
