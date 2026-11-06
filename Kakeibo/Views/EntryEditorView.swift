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
    /// Type a new entry starts as (Home's Transfer button opens it as a transfer).
    var initialKind: EntryKind = .expense

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
    /// Set once the starting values are in, so filling them in doesn't vibrate.
    @State private var ready = false
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

                // Everything you touch while entering sits in the bottom half, in reach of one thumb:
                // categories right above the number pad, the pad itself at the very bottom.
                Spacer(minLength: 0)
                if kind == .transfer {
                    KeypadView(amount: $amount)
                    Button {
                        save(categoryID: nil)
                    } label: {
                        Text(editing == nil ? "Save transfer" : "Save")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSaveTransfer)
                } else {
                    categoryGrid
                    KeypadView(amount: $amount)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            // Typing a note brings up the keyboard over the number pad instead of squashing the screen.
            .ignoresSafeArea(.keyboard, edges: .bottom)
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
            .sensoryFeedback(.selection, trigger: kind) { _, _ in ready }
            .sensoryFeedback(.selection, trigger: split) { _, _ in ready }
            .sensoryFeedback(.selection, trigger: isRefund) { _, _ in ready }
            .sensoryFeedback(.selection, trigger: accountID) { _, _ in ready }
            .sensoryFeedback(.selection, trigger: toAccountID) { _, _ in ready }
            .sensoryFeedback(.selection, trigger: Calendar.kakeibo.startOfDay(for: date)) { _, _ in ready }
        }
    }

    // MARK: Pieces

    private var amountDisplay: some View {
        VStack(spacing: 2) {
            Text(Yen.format(amount))
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(amount == 0 ? Color.secondary : Color.primary)
                .contentTransition(.numericText())
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
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.tileFill))
    }

    /// Hugs its tiles so they sit right on top of the number pad; scrolls only if there are too many to fit.
    private var categoryGrid: some View {
        ViewThatFits(in: .vertical) {
            categoryTiles
            ScrollView {
                categoryTiles
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    private var categoryTiles: some View {
        VStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(visibleCategories) { category in
                    Button {
                        save(categoryID: category.id)
                    } label: {
                        let look = CategoryLook.of(category)
                        let selected = category.id == editing?.categoryID
                        VStack(spacing: 5) {
                            if let symbol = look.symbol {
                                Image(systemName: symbol)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(look.tint)
                            } else {
                                Text(category.emoji).font(.title3)
                            }
                            Text(category.name)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.22) : Color.tileFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
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
        Haptics.prepare()
        defer { DispatchQueue.main.async { ready = true } }
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
            kind = initialKind
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
        if endsOverBudget(entry) {
            Haptics.warning()
        } else {
            Haptics.success()
        }
        dismiss()
    }

    /// A spending entry that leaves its category over budget gets a warning buzz instead of success.
    private func endsOverBudget(_ entry: Entry) -> Bool {
        guard entry.kind == .expense, !entry.isRefund, entry.myShare > 0 else { return false }
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        return Ledger(accounts: accounts, categories: categories, entries: all)
            .isOverBudget(categoryID: entry.categoryID, inMonthOf: entry.date)
    }

    private func deleteEntry() {
        guard let entry = editing else { return }
        context.delete(entry)
        context.saveAndRefresh()
        Haptics.warning()
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
                            .sensoryFeedback(trigger: entry.isConfirmed) { _, confirmed in
                                confirmed ? SensoryFeedback.success : SensoryFeedback.selection
                            }
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
                    Haptics.warning()
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
