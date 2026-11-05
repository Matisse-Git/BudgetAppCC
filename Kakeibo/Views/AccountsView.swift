import SwiftData
import SwiftUI

struct AccountsView: View {
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var entries: [Entry]
    @State private var creating = false

    var body: some View {
        let ledger = Ledger(accounts: accounts, entries: entries)
        NavigationStack {
            List {
                ForEach(AccountKind.allCases) { kind in
                    let items = accounts.filter { $0.kind == kind && !$0.isArchived }
                    if !items.isEmpty {
                        Section(kind.label) {
                            ForEach(items) { account in
                                NavigationLink {
                                    AccountDetailView(account: account)
                                } label: {
                                    AccountRow(account: account, ledger: ledger)
                                }
                            }
                        }
                    }
                }
                let archived = accounts.filter { $0.isArchived }
                if !archived.isEmpty {
                    Section("Archived") {
                        ForEach(archived) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                AccountRow(account: account, ledger: ledger).opacity(0.6)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        creating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                AccountEditView(account: nil)
            }
        }
    }
}

struct AccountRow: View {
    let account: Account
    let ledger: Ledger

    var body: some View {
        HStack(spacing: 12) {
            Text(account.emoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if account.tracksBalance {
                let value = ledger.balance(of: account)
                Text(Yen.format(account.kind == .credit ? max(-value, 0) : value))
                    .monospacedDigit()
                    .foregroundStyle(account.kind != .credit && value < 0 ? Color.red : Color.primary)
            }
        }
    }

    private var detail: String? {
        if account.kind == .credit {
            let status = Billing.status(for: account, ledger: ledger)
            if status.due > 0 {
                return "Due \(status.dueDate.formatted(.dateTime.day().month(.abbreviated))): \(Yen.format(status.due))"
                    + (status.isOverdue ? " (overdue)" : "")
            }
            return "Next bill so far: \(Yen.format(status.nextSoFar))"
        }
        if !account.tracksBalance {
            return "Top-ups count as spending"
        }
        return nil
    }
}

struct AccountDetailView: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @State private var editingAccount = false
    @State private var editing: Entry?
    @State private var adjusting = false
    @State private var adjustText = ""

    var body: some View {
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let lookup = Lookup(accounts: accounts, categories: categories)
        let related = entries.filter { $0.accountID == account.id || $0.toAccountID == account.id }
        List {
            Section {
                if account.kind == .credit {
                    creditSummary(ledger: ledger)
                } else if account.tracksBalance {
                    LabeledContent("Balance") {
                        Text(Yen.format(ledger.balance(of: account))).font(.title2.bold()).monospacedDigit()
                    }
                } else {
                    Text("Top-ups to this account count as spending, so it has no balance.")
                        .foregroundStyle(.secondary)
                }
                if account.tracksBalance {
                    Button(account.kind == .credit ? "Correct unpaid amount" : "Adjust balance") {
                        let value = ledger.balance(of: account)
                        adjustText = String(account.kind == .credit ? -value : value)
                        adjusting = true
                    }
                }
            }
            Section("Entries") {
                if related.isEmpty {
                    Text("No entries yet.").foregroundStyle(.secondary)
                }
                ForEach(related.prefix(200)) { entry in
                    Button {
                        editing = entry
                    } label: {
                        EntryRow(entry: entry, lookup: lookup)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(account.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editingAccount = true }
            }
        }
        .sheet(isPresented: $editingAccount) {
            AccountEditView(account: account)
        }
        .sheet(item: $editing) { entry in
            EntryEditorRouter(entry: entry)
        }
        .alert(account.kind == .credit ? "Real unpaid amount" : "Real balance", isPresented: $adjusting) {
            TextField("¥", text: $adjustText)
                .keyboardType(.numbersAndPunctuation)
            Button("Save") { applyAdjustment(ledger: ledger) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The difference is saved as an adjustment. It never counts as spending.")
        }
    }

    @ViewBuilder
    private func creditSummary(ledger: Ledger) -> some View {
        let status = Billing.status(for: account, ledger: ledger)
        VStack(alignment: .leading, spacing: 6) {
            if status.due > 0 {
                Text("Due \(status.dueDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(.subheadline)
                    .foregroundStyle(status.isOverdue ? Color.red : Color.secondary)
                Text(Yen.format(status.due)).font(.largeTitle.bold()).monospacedDigit()
            } else {
                Text("Nothing due right now").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Next bill so far: \(Yen.format(status.nextSoFar)) · due \(status.nextDueDate.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.subheadline)
            Text("Closes \(account.closingDay == 31 ? "at end of month" : "on day \(account.closingDay)"), paid on day \(account.paymentDay) of the next month from \(ledger.account(account.payFromAccountID)?.name ?? "(not set)")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if status.due > 0 {
            Button("Record payoff of \(Yen.format(status.due)) now") {
                recordPayoff(amount: status.due, ledger: ledger)
            }
            .disabled(account.payFromAccountID == nil)
        }
    }

    private func recordPayoff(amount: Int, ledger: Ledger) {
        guard let from = account.payFromAccountID else { return }
        let payoff = Entry(kind: .payoff, amount: amount, date: Date(), accountID: from, toAccountID: account.id)
        payoff.billCycleKey = Billing.latestCycle(for: account, now: Date()).key(for: account.id)
        payoff.isConfirmed = true
        context.insert(payoff)
        context.saveAndRefresh()
        Haptics.success()
    }

    private func applyAdjustment(ledger: Ledger) {
        guard let real = Yen.parse(adjustText) else { return }
        let current = ledger.balance(of: account)
        let target = account.kind == .credit ? -real : real
        let delta = target - current
        guard delta != 0 else { return }
        let entry = Entry(kind: .adjust, amount: delta, date: Date(), accountID: account.id)
        context.insert(entry)
        context.saveAndRefresh()
    }
}

struct AccountEditView: View {
    let account: Account?

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
        guard let account else { return }
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
            target = Account(name: name, kind: kind, sortOrder: (accounts.map(\.sortOrder).max() ?? 0) + 1)
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
