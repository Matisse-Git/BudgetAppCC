import SwiftData
import SwiftUI

/// The Accounts tab (Accounts artboard): net worth, then bank accounts, prepaid wallets and cash with
/// their totals and a status line each, then credit cards with what's due and what's building.
struct AccountsView: View {
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var entries: [Entry]
    @AppStorage(SettingsKey.groupAccountsByType) private var groupByType = true
    @State private var creatingKind: AccountKind?
    @State private var creatingCard = false
    @State private var reordering = false

    var body: some View {
        let now = Date()
        let ledger = Ledger(accounts: accounts, entries: entries)
        let reminders = Billing.reminders(ledger: ledger, now: now)
        let cards = AccountLayout.cards(accounts)
        let groups = AccountLayout.moneyGroups(accounts, byType: groupByType)
        let money = groups.flatMap(\.accounts).filter(\.holdsMoney)
        let have = money.reduce(0) { $0 + ledger.balance(of: $1, before: now) }
        let owed = cards.reduce(0) { $0 + max(-ledger.balance(of: $1, before: now), 0) }
        let archived = AccountLayout.sorted(accounts.filter(\.isArchived))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    netWorth(have: have, owed: owed)
                        .padding(.top, 8)
                    ForEach(groups) { group in
                        SectionCaps(title: groupTitle(group), trailing: Yen.format(groupTotal(group, ledger: ledger, now: now)))
                            .padding(.top, Metrics.sectionSpacing)
                        CardList {
                            ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                                if index > 0 { ListDivider() }
                                NavigationLink {
                                    AccountDetailView(account: account)
                                } label: {
                                    MoneyAccountRow(account: account, ledger: ledger, reminders: reminders, now: now)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                    if !cards.isEmpty {
                        SectionCaps(title: "Credit cards", trailing: "\(Yen.format(owed)) owed")
                            .padding(.top, Metrics.sectionSpacing)
                        CardList {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                if index > 0 { ListDivider(inset: 64) }
                                NavigationLink {
                                    AccountDetailView(account: card)
                                } label: {
                                    CreditCardRow(card: card, ledger: ledger, reminders: reminders, now: now)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                        Text("Owed includes spending that hasn't been billed yet.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    if !archived.isEmpty {
                        SectionCaps(title: "Archived")
                            .padding(.top, Metrics.sectionSpacing)
                        CardList {
                            ForEach(Array(archived.enumerated()), id: \.element.id) { index, account in
                                if index > 0 { ListDivider() }
                                NavigationLink {
                                    AccountDetailView(account: account)
                                } label: {
                                    KRow(account.name, subtitle: account.kind.label, chevron: true) {
                                        AccountIcon(account: account)
                                    } trailing: {
                                        EmptyView()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                        .opacity(0.6)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
            }
            .kScreenBackground()
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { reordering = true }
                        .accessibilityHint("Reorder accounts and choose whether to group them by type")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { creatingKind = .bank } label: { Label("Bank account", systemImage: AccountKind.bank.symbol) }
                        Button { creatingKind = .topUp } label: { Label("Prepaid wallet", systemImage: "wave.3.right") }
                        Button { creatingKind = .cash } label: { Label("Cash", systemImage: AccountKind.cash.symbol) }
                        Button { creatingCard = true } label: { Label("Credit card", systemImage: AccountKind.credit.symbol) }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add account")
                }
            }
            .sheet(item: $creatingKind) { kind in
                AccountEditView(account: nil, initialKind: kind)
            }
            .sheet(isPresented: $creatingCard) {
                CardSetupView(card: nil)
            }
            .sheet(isPresented: $reordering) {
                ReorderAccountsView()
            }
        }
    }

    private func netWorth(have: Int, owed: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Net worth")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(Yen.format(have - owed))
                .font(.kStat)
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 4)
            HStack(alignment: .top, spacing: 12) {
                stat("Money you have", Yen.format(have))
                stat("Owed on cards", Yen.format(owed))
            }
            .padding(.top, 14)
        }
        .kCard(padding: 18)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupTitle(_ group: AccountGroup) -> String {
        switch group.id {
        case AccountKind.bank.rawValue: return "Bank accounts"
        case AccountKind.topUp.rawValue: return "Prepaid wallets"
        case AccountKind.cash.rawValue: return "Cash"
        default: return group.title
        }
    }

    private func groupTotal(_ group: AccountGroup, ledger: Ledger, now: Date) -> Int {
        group.accounts.filter(\.tracksBalance).reduce(0) { $0 + ledger.balance(of: $1, before: now) }
    }
}

/// A bank, prepaid or cash account: balance and the one thing worth knowing about it.
struct MoneyAccountRow: View {
    let account: Account
    let ledger: Ledger
    let reminders: [BillReminder]
    var now = Date()

    var body: some View {
        let line = statusLine
        KRow(account.name, chevron: true) {
            AccountIcon(account: account)
        } subtitle: {
            if line.warning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                    Text(line.text)
                }
                .fontWeight(.semibold)
                .foregroundStyle(Palette.warning)
            } else {
                Text(line.text)
            }
        } trailing: {
            if account.tracksBalance {
                let balance = ledger.balance(of: account, before: now)
                Text(Yen.format(balance))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(balance < 0 ? Palette.negativeText : Palette.textPrimary)
            }
        }
    }

    private var statusLine: (text: String, warning: Bool) {
        let paid = reminders.filter { $0.payFrom?.id == account.id }
        if let short = paid.first(where: { $0.shortfall > 0 }) {
            return ("\(Yen.format(short.shortfall)) short for \(short.dueDate.formatted(.dateTime.month(.abbreviated).day()))", true)
        }
        if !account.tracksBalance {
            return ("Top-ups count as spending", false)
        }
        let cards = ledger.accounts.filter { $0.kind == .credit && !$0.isArchived && $0.payFromAccountID == account.id }
        if !cards.isEmpty {
            return ("Pays \(AccountText.list(cards.map(\.name)))", false)
        }
        if let last = ledger.entries
            .filter({ $0.date <= now && Ledger.effect(of: $0, on: account.id) != 0 })
            .max(by: { $0.date < $1.date }) {
            let change = Ledger.effect(of: last, on: account.id)
            let when = Calendar.kakeibo.isDateInToday(last.date) ? "today" : "on \(last.date.formatted(.dateTime.month(.abbreviated).day()))"
            return ("\(Yen.format(change, showPlus: true)) \(when)", false)
        }
        switch account.kind {
        case .cash: return ("Cash on hand", false)
        case .topUp: return ("Prepaid balance", false)
        default: return ("Bank account", false)
        }
    }
}

/// A credit card: the statement due and its date, and the next bill so far.
struct CreditCardRow: View {
    let card: Account
    let ledger: Ledger
    let reminders: [BillReminder]
    var now = Date()

    var body: some View {
        let status = Billing.status(for: card, ledger: ledger, now: now)
        let short = reminders.first { $0.account.id == card.id }.map { $0.shortfall > 0 } ?? false
        KRow(card.name, subtitle: "Next bill so far \(Yen.format(status.nextSoFar))", minHeight: 64, chevron: true) {
            AccountIcon(account: card)
        } trailing: {
            if status.due > 0 {
                AmountStack(Yen.format(status.due)) {
                    if status.isOverdue {
                        Text("Overdue").fontWeight(.semibold).foregroundStyle(Palette.negativeText)
                    } else if short {
                        Text("Due \(status.dueDate.formatted(.dateTime.month(.abbreviated).day())) · short")
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.warning)
                    } else {
                        Text("Due \(status.dueDate.formatted(.dateTime.month(.abbreviated).day()))")
                    }
                }
            } else {
                AmountStack(Yen.format(max(status.owedNow, 0)), caption: "Nothing due")
            }
        }
    }
}

enum AccountText {
    /// "Everyday & Travel cards" when every name ends in "Card", otherwise "A, B & C".
    static func list(_ names: [String]) -> String {
        let suffix = " Card"
        if names.count > 1, names.allSatisfy({ $0.hasSuffix(suffix) }) {
            let short = names.map { String($0.dropLast(suffix.count)) }
            return join(short) + " cards"
        }
        return join(names)
    }

    private static func join(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " & " + last
    }
}

/// Opens the right page for an account.
struct AccountDetailView: View {
    let account: Account

    var body: some View {
        if account.kind == .credit {
            CreditCardView(card: account)
        } else {
            BankAccountView(account: account)
        }
    }
}

/// Drag accounts into your own order, and choose whether non-card accounts are split by type.
struct ReorderAccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage(SettingsKey.groupAccountsByType) private var groupByType = true

    var body: some View {
        let groups = AccountLayout.editGroups(accounts, byType: groupByType)
        NavigationStack {
            List {
                Section {
                    Toggle("Group by type", isOn: $groupByType)
                        .sensoryFeedback(.selection, trigger: groupByType)
                } footer: {
                    Text("Splits your other accounts into Bank, Top-up and Cash. Your order is kept either way.")
                }
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    Section(group.title) {
                        ForEach(group.accounts) { account in
                            HStack(spacing: 12) {
                                AccountIcon(account: account, size: 30)
                                Text(account.name)
                            }
                        }
                        .onMove { source, destination in
                            AccountLayout.move(group: index, from: source, to: destination, in: groups, all: accounts)
                            try? context.save()
                            Haptics.lift()
                        }
                    }
                }
                Section {
                } footer: {
                    Text("Drag to reorder. The same order is used in every account picker. Archived accounts stay at the bottom of the Accounts tab.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AccountEditView: View {
    let account: Account?
    /// Type a new account starts as (the Accounts tab's + menu).
    var initialKind: AccountKind = .bank

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]

    @State private var name = ""
    @State private var emoji = ""
    @State private var kind: AccountKind = .bank
    @State private var opening = 0
    @State private var closingDay = 31
    @State private var paymentDay = 27
    @State private var payFrom: UUID?
    @State private var autoPayoff = true
    @State private var countsTopUp = false
    @State private var topUpCategory: UUID?
    @State private var walletName = ""
    @State private var archived = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Emoji", text: $emoji)
                    Picker("Type", selection: $kind) {
                        ForEach(AccountKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                }
                if kind == .topUp {
                    Section {
                        Toggle("Top-ups count as spending", isOn: $countsTopUp)
                            .sensoryFeedback(.selection, trigger: countsTopUp)
                        if countsTopUp {
                            Picker("Category", selection: $topUpCategory) {
                                Text("None").tag(UUID?.none)
                                ForEach(categories.filter { $0.kind == .expense && !$0.isArchived }) { category in
                                    Text(category.displayName).tag(Optional(category.id))
                                }
                            }
                        }
                    } footer: {
                        Text("Turn this on for cards like PASMO: each top-up counts as spending, and you don't log individual rides.")
                    }
                }
                if !(kind == .topUp && countsTopUp) {
                    Section {
                        AmountField(title: kind == .credit ? "Unpaid when added" : "Starting balance", value: $opening, allowNegative: kind != .credit)
                    } footer: {
                        Text("Use Adjust on the account page to correct the balance later.")
                    }
                }
                if kind == .credit {
                    Section("Billing") {
                        DayPicker(title: "Closing day (締め日)", day: $closingDay)
                        DayPicker(title: "Payment day (支払日)", day: $paymentDay)
                        Picker("Paid from", selection: $payFrom) {
                            Text("Not set").tag(UUID?.none)
                            ForEach(accounts.filter { $0.holdsMoney && !$0.isArchived && $0.id != account?.id }) { other in
                                Text(other.displayName).tag(Optional(other.id))
                            }
                        }
                        Toggle("Record payoff automatically", isOn: $autoPayoff)
                            .sensoryFeedback(.selection, trigger: autoPayoff)
                    }
                }
                Section {
                    TextField("Name in Apple Wallet (optional)", text: $walletName)
                } footer: {
                    Text("Used to match payments logged by a Shortcuts automation.")
                }
                if account != nil {
                    Section {
                        Toggle("Archived", isOn: $archived)
                            .sensoryFeedback(.selection, trigger: archived)
                    } footer: {
                        Text("Archived accounts are hidden from pickers but keep their history.")
                    }
                }
            }
            .navigationTitle(account == nil ? "New account" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let account else {
            kind = initialKind
            return
        }
        name = account.name
        emoji = account.emoji
        kind = account.kind
        opening = account.kind == .credit ? -account.openingBalance : account.openingBalance
        closingDay = account.closingDay
        paymentDay = account.paymentDay
        payFrom = account.payFromAccountID
        autoPayoff = account.autoPayoff
        countsTopUp = account.countsTopUpAsSpending
        topUpCategory = account.topUpCategoryID
        walletName = account.walletCardName
        archived = account.isArchived
    }

    private func save() {
        let target: Account
        if let account {
            target = account
        } else {
            target = Account(name: name, kind: kind, sortOrder: AccountLayout.nextSortOrder(accounts))
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.kind = kind
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        target.emoji = trimmedEmoji.isEmpty ? kind.defaultEmoji : String(trimmedEmoji.prefix(1))
        target.openingBalance = kind == .credit ? -abs(opening) : opening
        target.closingDay = closingDay
        target.paymentDay = paymentDay
        target.payFromAccountID = kind == .credit ? payFrom : nil
        target.autoPayoff = autoPayoff
        target.countsTopUpAsSpending = kind == .topUp && countsTopUp
        target.topUpCategoryID = target.countsTopUpAsSpending ? topUpCategory : nil
        target.walletCardName = walletName.trimmingCharacters(in: .whitespaces)
        target.isArchived = archived
        context.saveAndRefresh()
        dismiss()
    }
}
