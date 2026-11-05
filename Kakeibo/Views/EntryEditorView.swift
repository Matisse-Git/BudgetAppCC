import SwiftData
import SwiftUI

enum SplitMode: String, CaseIterable, Identifiable {
    case none, half, allHers, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Just me"
        case .half: return "Split 50/50"
        case .allHers: return "All hers"
        case .custom: return "Custom share"
        }
    }
}

/// The fast path: type an amount, tap a category, done.
struct EntryEditorView: View {
    enum Mode {
        case new
        case edit(Entry)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName

    @State private var kind: EntryKind = .expense
    @State private var amount = 0
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var split: SplitMode = .none
    @State private var customShare = 0
    @State private var isRefund = false
    @State private var loaded = false
    @State private var confirmDelete = false

    private var editing: Entry? {
        if case .edit(let entry) = mode { return entry }
        return nil
    }

    private var spendAccounts: [Account] {
        accounts.filter { ($0.tracksBalance && !$0.isArchived) || $0.id == editing?.accountID }
    }

    private var transferAccounts: [Account] {
        accounts.filter { !$0.isArchived || $0.id == editing?.accountID || $0.id == editing?.toAccountID }
    }

    private var visibleCategories: [BudgetCategory] {
        let wanted: CategoryKind = kind == .income ? .income : .expense
        return categories.filter { $0.kind == wanted && (!$0.isArchived || $0.id == editing?.categoryID) }
    }

    private var partnerShare: Int {
        guard kind == .expense, !isRefund else { return 0 }
        switch split {
        case .none: return 0
        case .half: return amount / 2
        case .allHers: return amount
        case .custom: return min(max(customShare, 0), amount)
        }
    }

    private var canSaveTransfer: Bool {
        amount > 0 && accountID != nil && toAccountID != nil && accountID != toAccountID
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("Type", selection: $kind) {
                    Text("Expense").tag(EntryKind.expense)
                    Text("Income").tag(EntryKind.income)
                    Text("Transfer").tag(EntryKind.transfer)
                }
                .pickerStyle(.segmented)

                amountDisplay
                optionsRow
                if kind == .expense && split == .custom && !isRefund {
                    AmountField(title: "\(partnerName)'s share", value: $customShare)
                        .padding(.horizontal, 4)
                }
                TextField("Note (optional)", text: $note)
                    .textFieldStyle(.roundedBorder)
                KeypadView(amount: $amount)
                if kind == .transfer {
                    Button {
                        save(categoryID: nil)
                    } label: {
                        Text(editing == nil ? "Save transfer" : "Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSaveTransfer)
                    Spacer(minLength: 0)
                } else {
                    categoryGrid
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .navigationTitle(editing == nil ? "New entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if editing != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteEntry)
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Pieces

    private var amountDisplay: some View {
        VStack(spacing: 2) {
            Text(Yen.format(amount))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if partnerShare > 0 {
                Text("You \(Yen.format(amount - partnerShare)) · \(partnerName) \(Yen.format(partnerShare))")
                    .font(.footnote)
                    .foregroundStyle(.pink)
            } else if isRefund && kind == .expense {
                Text("Refund: reduces spending")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else if kind != .transfer && amount > 0 {
                Text(editing == nil ? "Tap a category to save" : "Tap a category to save changes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var optionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if kind == .transfer {
                    accountMenu(placeholder: "From", selection: $accountID, options: transferAccounts)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    accountMenu(placeholder: "To", selection: $toAccountID, options: transferAccounts)
                } else {
                    accountMenu(placeholder: "Account", selection: $accountID, options: spendAccounts)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                if kind == .expense {
                    Menu {
                        Picker("Split", selection: $split) {
                            ForEach(SplitMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        Toggle("Refund", isOn: $isRefund)
                    } label: {
                        chip(isRefund ? "Refund" : split.label, systemImage: split == .none ? "person" : "person.2.fill")
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func accountMenu(placeholder: String, selection: Binding<UUID?>, options: [Account]) -> some View {
        let current = accounts.first { $0.id == selection.wrappedValue }
        return Menu {
            Picker(placeholder, selection: selection) {
                ForEach(options) { account in
                    Text(account.displayName).tag(Optional(account.id))
                }
            }
        } label: {
            chip(current?.displayName ?? placeholder, systemImage: nil)
        }
    }

    private func chip(_ text: String, systemImage: String?) -> some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(1)
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.chip))
    }

    private var categoryGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(visibleCategories) { category in
                    Button {
                        save(categoryID: category.id)
                    } label: {
                        VStack(spacing: 2) {
                            Text(category.emoji).font(.title2)
                            Text(category.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(category.id == editing?.categoryID ? Color.accentColor.opacity(0.25) : Color.chip)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(amount == 0)
                    .opacity(amount == 0 ? 0.5 : 1)
                }
            }
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let entry = editing {
            kind = entry.kind
            amount = entry.amount
            accountID = entry.accountID
            toAccountID = entry.toAccountID
            date = entry.date
            note = entry.note
            isRefund = entry.isRefund
            if entry.partnerShare == 0 {
                split = .none
            } else if entry.partnerShare == entry.amount {
                split = .allHers
            } else if entry.partnerShare == entry.amount / 2 {
                split = .half
            } else {
                split = .custom
                customShare = entry.partnerShare
            }
        } else {
            let preferred = UUID(uuidString: defaultAccountID)
            accountID = spendAccounts.first { $0.id == preferred }?.id ?? spendAccounts.first?.id
            if DemoMode.isOn {
                amount = 3_600
                split = .half
            }
        }
    }

    private func save(categoryID: UUID?) {
        guard amount > 0 else { return }
        if kind == .transfer && !canSaveTransfer { return }
        let entry = editing ?? Entry(kind: kind, amount: amount)
        entry.kind = kind
        entry.amount = amount
        entry.date = date
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.accountID = accountID
        entry.toAccountID = kind == .transfer ? toAccountID : nil
        entry.categoryID = kind == .transfer ? nil : categoryID
        entry.isRefund = kind == .expense && isRefund
        entry.partnerShare = partnerShare
        entry.needsReview = false
        if editing == nil { context.insert(entry) }
        context.saveAndRefresh()
        Haptics.success()
        dismiss()
    }

    private func deleteEntry() {
        guard let entry = editing else { return }
        context.delete(entry)
        context.saveAndRefresh()
        dismiss()
    }
}

/// Simple form for card payoffs, repayments and balance adjustments.
struct EntryDetailForm: View {
    @Bindable var entry: Entry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var confirmDelete = false

    private var moneyAccounts: [Account] { accounts.filter { $0.holdsMoney || $0.id == entry.accountID } }
    private var creditAccounts: [Account] { accounts.filter { $0.kind == .credit || $0.id == entry.toAccountID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Type", value: entry.kind.label)
                    AmountField(title: entry.kind == .adjust ? "Change" : "Amount", value: $entry.amount, allowNegative: entry.kind == .adjust)
                    DatePicker("Date", selection: $entry.date)
                }
                Section {
                    switch entry.kind {
                    case .payoff:
                        accountPicker("Paid from", selection: $entry.accountID, options: moneyAccounts)
                        accountPicker("Card", selection: $entry.toAccountID, options: creditAccounts)
                    case .settlement:
                        accountPicker("Received in", selection: $entry.accountID, options: moneyAccounts)
                    default:
                        accountPicker("Account", selection: $entry.accountID, options: accounts)
                    }
                }
                if entry.kind == .payoff {
                    Section {
                        Toggle("Confirmed", isOn: $entry.isConfirmed)
                    } footer: {
                        Text("Tick this once you've seen the real debit. Unconfirmed payoffs still move the money.")
                    }
                }
                Section {
                    TextField("Note", text: $entry.note)
                }
                Section {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(entry.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        entry.needsReview = false
                        context.saveAndRefresh()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    context.saveAndRefresh()
                    dismiss()
                }
            }
        }
    }

    private func accountPicker(_ title: String, selection: Binding<UUID?>, options: [Account]) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(UUID?.none)
            ForEach(options) { account in
                Text(account.displayName).tag(Optional(account.id))
            }
        }
    }
}
