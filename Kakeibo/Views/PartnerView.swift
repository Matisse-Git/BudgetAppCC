import SwiftData
import SwiftUI

/// What my partner owes for shared expenses, and her repayments.
struct PartnerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""

    @State private var settling = false
    @State private var repaying: Entry?
    @State private var editing: Entry?

    private var receivingAccounts: [Account] { accounts.filter { $0.holdsMoney && !$0.isArchived } }

    var body: some View {
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let lookup = Lookup(accounts: accounts, categories: categories)
        let remaining = ledger.partnerRemaining()
        let unpaid = ledger.sharedExpenses.filter { (remaining[$0.id] ?? 0) > 0 }.reversed()
        let owed = ledger.partnerOwed
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(owed >= 0 ? "\(partnerName) owes you" : "\(partnerName) has paid back extra")
                        .foregroundStyle(.secondary)
                    Text(Yen.format(abs(owed))).font(.largeTitle.bold()).monospacedDigit()
                }
                Button("Settle up…") { settling = true }
            }
            Section {
                if unpaid.isEmpty {
                    Text("Nothing outstanding.").foregroundStyle(.secondary)
                }
                ForEach(Array(unpaid)) { entry in
                    Button {
                        editing = entry
                    } label: {
                        TransactionRow(entry: entry, lookup: lookup, partnerName: partnerName, timeStyle: .relative)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .swipeActions {
                        Button("Repaid") { repaying = entry }.tint(Palette.positive)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let left = remaining[entry.id], left < entry.partnerShare {
                            Text("\(Yen.format(left)) left")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.warning)
                                .padding(.trailing, 16)
                                .padding(.bottom, 4)
                        }
                    }
                }
            } header: {
                Text("Not yet repaid")
            } footer: {
                Text("Swipe left on an item to mark it repaid. Settle up applies any amount to the oldest items first.")
            }
            if !ledger.settlements.isEmpty {
                Section("Repayments") {
                    ForEach(ledger.settlements) { entry in
                        Button {
                            editing = entry
                        } label: {
                            TransactionRow(entry: entry, lookup: lookup, partnerName: partnerName, timeStyle: .relative)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
        }
        .navigationTitle(partnerName)
        .sheet(isPresented: $settling) {
            SettleUpView(suggested: max(owed, 0))
        }
        .sheet(item: $editing) { entry in
            EntryEditorRouter(entry: entry)
        }
        .confirmationDialog("Where did the money go?", isPresented: Binding(get: { repaying != nil }, set: { if !$0 { repaying = nil } }), titleVisibility: .visible) {
            ForEach(receivingAccounts) { account in
                Button(account.displayName) {
                    if let item = repaying { markRepaid(item, amount: remaining[item.id] ?? 0, into: account.id) }
                }
            }
        }
    }

    private func markRepaid(_ item: Entry, amount: Int, into accountID: UUID) {
        guard amount > 0 else { return }
        let settlement = Entry(kind: .settlement, amount: amount, date: Date(), accountID: accountID)
        settlement.settlementTargetID = item.id
        settlement.note = item.merchant.isEmpty ? item.note : item.merchant
        context.insert(settlement)
        context.saveAndRefresh()
        repaying = nil
        Haptics.success()
    }
}

struct SettleUpView: View {
    let suggested: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName

    @State private var amount = 0
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var loaded = false

    private var receivingAccounts: [Account] { accounts.filter { $0.holdsMoney && !$0.isArchived } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "Amount", value: $amount)
                    Picker("Received in", selection: $accountID) {
                        ForEach(receivingAccounts) { account in
                            Text(account.displayName).tag(Optional(account.id))
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Repayments aren't income: they reduce what \(partnerName) owes and add to the account.")
                }
                if suggested > 0 {
                    Section {
                        Button("Everything: \(Yen.format(suggested))") { amount = suggested }
                    }
                }
            }
            .navigationTitle("Settle up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(amount <= 0 || accountID == nil)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let preferred = UUID(uuidString: defaultAccountID)
                accountID = receivingAccounts.first { $0.id == preferred }?.id ?? receivingAccounts.first?.id
            }
        }
    }

    private func save() {
        let settlement = Entry(kind: .settlement, amount: amount, date: date, accountID: accountID)
        settlement.note = note
        context.insert(settlement)
        context.saveAndRefresh()
        Haptics.success()
        dismiss()
    }
}
