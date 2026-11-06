import Foundation
import SwiftData
import SwiftUI

/// Preview mode for screenshots: launch with `-demo -screen <name>`.
/// Uses an in-memory database filled with sample data, so it never touches real data.
enum DemoMode {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-screen"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

/// Opens a single screen directly, for screenshots.
struct DemoScreen: View {
    let name: String
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    var body: some View {
        if name == "edit-home" {
            EditHomeView(order: .constant(HomeSection.defaultOrder), hidden: .constant(""))
        } else {
            screens
        }
    }

    private var screens: some View {
        NavigationStack {
            switch name {
            case "card":
                if let card = accounts.first(where: { $0.name == "Rakuten Card" }) {
                    AccountDetailView(account: card)
                } else {
                    ProgressView()
                }
            case "partner":
                PartnerView()
            case "settings":
                SettingsView()
            case "categories":
                CategoriesView()
            case "review":
                ReviewListView()
            default:
                EmptyView()
            }
        }
    }

    static let standalone: Set<String> = ["card", "partner", "settings", "categories", "review", "edit-home"]
}

enum DemoData {
    @MainActor
    static func populate(_ context: ModelContext, now: Date = Date()) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        func account(_ name: String) -> UUID? { accounts.first { $0.name == name }?.id }
        func category(_ name: String) -> UUID? { categories.first { $0.name == name }?.id }

        let budgets: [String: Int] = [
            // Konbini, Subscriptions and Other have no budget, so Budgets tucks them behind "See all categories".
            "Rent": 82_000, "Utilities": 12_000, "Phone": 5_000, "Transport": 10_000, "Supermarket": 40_000,
            "Restaurants": 20_000, "Shopping": 15_000,
        ]
        for c in categories { c.monthlyBudget = budgets[c.name] ?? 0 }

        let calendar = Calendar.kakeibo
        let today = calendar.component(.day, from: now)
        let thisMonth = Ledger.monthInterval(containing: now).start
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        func date(_ base: Date, _ day: Int, hour: Int = 12) -> Date {
            let clamped = base == thisMonth ? min(day, today) : day
            return calendar.date(byAdding: DateComponents(day: clamped - 1, hour: hour), to: base) ?? base
        }

        // Accounts: bank balance and a Rakuten bill due in 3 days that the bank can't quite cover.
        accounts.first { $0.name == "SMBC bank" }?.openingBalance = 150_000
        accounts.first { $0.name == "Revolut" }?.openingBalance = 12_400
        accounts.first { $0.name == "PayPay" }?.openingBalance = 3_200
        accounts.first { $0.name == "Cash" }?.openingBalance = 8_000
        if let rakuten = accounts.first(where: { $0.name == "Rakuten Card" }) {
            rakuten.paymentDay = min(today + 3, 28)
        }
        for a in accounts { a.createdAt = now }

        var entries: [Entry] = []
        func add(_ kind: EntryKind, _ amount: Int, _ when: Date, from: String?, to: String? = nil, category name: String? = nil,
                 merchant: String = "", note: String = "", share: Int = 0, review: Bool = false) {
            let e = Entry(kind: kind, amount: amount, date: when, accountID: from.flatMap(account),
                          toAccountID: to.flatMap(account), categoryID: name.flatMap(category))
            e.merchant = merchant
            e.note = note
            e.partnerShare = share
            e.needsReview = review
            entries.append(e)
        }

        // Last month: card purchases that make up the bills now due.
        add(.expense, 18_400, date(lastMonth, 4), from: "Rakuten Card", category: "Shopping", merchant: "Uniqlo")
        add(.expense, 12_300, date(lastMonth, 11), from: "Rakuten Card", category: "Supermarket", merchant: "Life")
        add(.expense, 9_800, date(lastMonth, 17), from: "Rakuten Card", category: "Utilities", note: "Tokyo Gas")
        add(.expense, 7_700, date(lastMonth, 22), from: "Rakuten Card", category: "Restaurants", merchant: "Torikizoku", share: 3_850)
        add(.expense, 22_600, date(lastMonth, 9), from: "SMBC Olive credit", category: "Supermarket", merchant: "Seijo Ishii")
        add(.expense, 4_980, date(lastMonth, 15), from: "SMBC Olive credit", category: "Phone", note: "Rakuten Mobile")
        add(.expense, 6_200, date(lastMonth, 27), from: "Paidy", category: "Shopping", merchant: "Amazon")

        // Earlier months, paid from the bank and covered by that month's salary, so the
        // charts have some history without changing today's balances.
        let history: [(back: Int, total: Int)] = [(5, 176_200), (4, 191_400), (3, 204_900), (2, 183_100), (1, 188_400)]
        let fillers: [(day: Int, category: String, merchant: String, weight: Int)] = [
            (3, "Supermarket", "Life", 9), (6, "Restaurants", "Sukiya", 5), (8, "Konbini", "Lawson", 2),
            (11, "Supermarket", "Seijo Ishii", 8), (14, "Transport", "", 4), (17, "Restaurants", "Ichiran", 6),
            (20, "Shopping", "Muji", 7), (23, "Supermarket", "Life", 9), (26, "Konbini", "FamilyMart", 2),
            (28, "Other", "", 3),
        ]
        let weightSum = fillers.reduce(0) { $0 + $1.weight }
        for month in history {
            guard let start = calendar.date(byAdding: .month, value: -month.back, to: thisMonth) else { continue }
            // Last month already holds 78,130 of card purchases (my share).
            let rest = month.total - 82_000 - (month.back == 1 ? 78_130 : 0)
            add(.expense, 82_000, date(start, 1, hour: 9), from: "SMBC bank", category: "Rent")
            var paid = 82_000
            var used = 0
            for (index, filler) in fillers.enumerated() {
                let amount = index == fillers.count - 1 ? rest - used : rest * filler.weight / weightSum
                used += amount
                paid += amount
                add(.expense, amount, date(start, filler.day, hour: 19), from: "SMBC bank",
                    category: filler.category, merchant: filler.merchant)
            }
            add(.income, paid, date(start, 25, hour: 10), from: "SMBC bank", category: "Salary")
        }

        // This month.
        add(.expense, 82_000, date(thisMonth, 1, hour: 9), from: "SMBC bank", category: "Rent")
        add(.transfer, 30_000, date(thisMonth, 1, hour: 10), from: "SMBC bank", to: "Revolut", note: "Monthly top-up")
        add(.transfer, 5_000, date(thisMonth, 2, hour: 8), from: "SMBC Olive credit", to: "PASMO")
        add(.expense, 1_490, date(thisMonth, 2), from: "Revolut", category: "Subscriptions", merchant: "Spotify")
        add(.expense, 3_480, date(thisMonth, 2, hour: 19), from: "SMBC Olive credit", category: "Supermarket", merchant: "Life")
        add(.expense, 6_400, date(thisMonth, 3, hour: 20), from: "SMBC Olive credit", category: "Restaurants", merchant: "Ichiran", share: 3_200)
        add(.expense, 820, date(thisMonth, 4, hour: 8), from: "PayPay", category: "Konbini", merchant: "Lawson")
        add(.expense, 4_200, date(thisMonth, 4, hour: 18), from: "Revolut", category: "Shopping", merchant: "Muji", share: 2_100)
        add(.settlement, 3_850, date(thisMonth, 4, hour: 21), from: "SMBC bank", note: "PayPay from her")
        add(.expense, 648, date(thisMonth, 5, hour: 9), from: "SMBC Olive credit", category: "Konbini", merchant: "FamilyMart", review: true)
        add(.expense, 2_980, date(thisMonth, 5, hour: 13), from: "Cash", category: "Restaurants", merchant: "Matsuya")

        entries.forEach { context.insert($0) }
        try? context.save()
    }
}
