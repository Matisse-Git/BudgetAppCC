import SwiftData
import SwiftUI

extension SplitMode {
    /// The split that produces this partner share.
    static func matching(share: Int, amount: Int) -> SplitMode {
        if share <= 0 { return .none }
        if share == amount { return .allHers }
        if share == amount / 2 { return .half }
        return .custom
    }

    /// Partner's part of `amount` under this split.
    func share(of amount: Int, custom: Int) -> Int {
        switch self {
        case .none: return 0
        case .half: return amount / 2
        case .allHers: return amount
        case .custom: return min(max(custom, 0), amount)
        }
    }
}

/// Settings → Quick entries: add, edit, reorder and delete.
struct QuickEntriesView: View {
    /// True when shown on its own (from the widget link) rather than pushed from Settings.
    var showsDone = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \QuickEntry.sortOrder) private var stored: [QuickEntry]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @State private var editing: QuickEntry?
    @State private var creating = false

    private var items: [QuickEntry] { QuickEntries.sorted(stored) }

    var body: some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        List {
            if items.isEmpty {
                Section {
                    Text("No quick entries yet. Tap + to add one, or edit an expense and choose ⋯ › Save as Quick Entry.")
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                Section {
                    ForEach(items) { item in
                        Button {
                            editing = item
                        } label: {
                            row(item, lookup: lookup)
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } footer: {
                    Text("They appear in this order on the add screen and in the Quick entries widget (2 in small, 4 in medium, 8 in large). To add the widget, long-press the Home Screen or the swipe-right screen → Edit → Add Widget → Kakeibo.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .kScreenBackground()
        .navigationTitle("Quick Entries")
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !items.isEmpty { EditButton() }
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add quick entry")
            }
        }
        .sheet(item: $editing) { item in
            QuickEntryEditView(quickEntry: item)
        }
        .sheet(isPresented: $creating) {
            QuickEntryEditView(draft: QuickEntryDraft())
        }
    }

    private func row(_ item: QuickEntry, lookup: Lookup) -> some View {
        let category = lookup.category(item.categoryID)
        let account = item.accountID.flatMap { lookup.accounts[$0] }
        var details = [category?.name ?? "No category", account?.name ?? "Default account"]
        if !item.merchant.isEmpty { details.append(item.merchant) }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(item.emoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(details.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                if let warning = warning(category: category, account: account, item: item) {
                    Text(warning)
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Yen.format(item.amount))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
                if item.partnerShare > 0 {
                    Text("mine \(Yen.format(item.amount - item.partnerShare))")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func warning(category: BudgetCategory?, account: Account?, item: QuickEntry) -> String? {
        var problems: [String] = []
        if category?.isArchived == true { problems.append("archived category") }
        if account?.isArchived == true { problems.append("archived account") }
        if item.accountID != nil && account == nil { problems.append("account deleted, uses the default") }
        guard !problems.isEmpty else { return nil }
        let text = problems.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = items
        list.move(fromOffsets: source, toOffset: destination)
        for (index, item) in list.enumerated() { item.sortOrder = index }
        context.saveAndRefresh()
        Haptics.lift()
    }

    private func delete(at offsets: IndexSet) {
        let list = items
        for index in offsets { context.delete(list[index]) }
        context.saveAndRefresh()
        Haptics.warning()
    }
}

/// Starting values for the quick entry editor.
struct QuickEntryDraft {
    var name = ""
    /// Empty means "use the category's emoji".
    var emoji = ""
    var amount = 0
    var categoryID: UUID?
    var accountID: UUID?
    var merchant = ""
    var partnerShare = 0

    init() {}

    init(_ quickEntry: QuickEntry) {
        name = quickEntry.name
        emoji = quickEntry.emoji
        amount = quickEntry.amount
        categoryID = quickEntry.categoryID
        accountID = quickEntry.accountID
        merchant = quickEntry.merchant
        partnerShare = quickEntry.partnerShare
    }

    /// From an existing expense ("Save as quick entry…"). Named after its note, else its merchant, else its category.
    init(entry: Entry, categories: [BudgetCategory]) {
        let categoryName = categories.first { $0.id == entry.categoryID }?.name ?? ""
        name = !entry.note.isEmpty ? entry.note : (!entry.merchant.isEmpty ? entry.merchant : categoryName)
        amount = entry.amount
        categoryID = entry.categoryID
        accountID = entry.accountID
        merchant = entry.merchant
        partnerShare = entry.partnerShare
    }
}

struct QuickEntryEditView: View {
    let quickEntry: QuickEntry?
    let start: QuickEntryDraft

    init(quickEntry: QuickEntry) {
        self.quickEntry = quickEntry
        self.start = QuickEntryDraft(quickEntry)
    }

    init(draft: QuickEntryDraft) {
        self.quickEntry = nil
        self.start = draft
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \QuickEntry.sortOrder) private var all: [QuickEntry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName

    @State private var draft = QuickEntryDraft()
    @State private var split: SplitMode = .none
    @State private var customShare = 0
    @State private var loaded = false
    @State private var confirmDelete = false

    private var category: BudgetCategory? { categories.first { $0.id == draft.categoryID } }
    private var account: Account? { accounts.first { $0.id == draft.accountID } }

    private var categoryOptions: [BudgetCategory] {
        categories.filter { $0.kind == .expense && (!$0.isArchived || $0.id == draft.categoryID) }
    }

    private var accountOptions: [Account] {
        accounts.filter { ($0.tracksBalance && !$0.isArchived) || $0.id == draft.accountID }
    }

    private var partnerShare: Int { split.share(of: draft.amount, custom: customShare) }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.amount > 0 && draft.categoryID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Breakfast)", text: $draft.name)
                    TextField("Emoji", text: $draft.emoji, prompt: Text(category?.emoji ?? "Emoji"))
                    AmountField(title: "Amount", value: $draft.amount)
                } footer: {
                    Text("Leave the emoji empty to use the category's. The name becomes the entry's note.")
                }
                Section {
                    Picker("Category", selection: $draft.categoryID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(categoryOptions) { option in
                            Text(option.displayName).tag(Optional(option.id))
                        }
                    }
                    Picker("Account", selection: $draft.accountID) {
                        Text("Default account").tag(UUID?.none)
                        ForEach(accountOptions) { option in
                            Text(option.displayName).tag(Optional(option.id))
                        }
                    }
                    TextField("Merchant (optional)", text: $draft.merchant)
                } footer: {
                    if category?.isArchived == true || account?.isArchived == true {
                        Text("Archived \(category?.isArchived == true ? "category" : "account"). It still logs, but you may want to pick another.")
                            .foregroundStyle(Palette.warning)
                    }
                }
                Section {
                    Picker("Split", selection: $split) {
                        ForEach(SplitMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    if split == .custom {
                        AmountField(title: "\(partnerName)'s share", value: $customShare)
                    }
                } footer: {
                    if partnerShare > 0 {
                        Text("You \(Yen.format(draft.amount - partnerShare)) · \(partnerName) \(Yen.format(partnerShare))")
                    }
                }
                if quickEntry != nil {
                    Section {
                        Button("Delete quick entry", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.sheet.ignoresSafeArea())
            .navigationTitle(quickEntry == nil ? "New Quick Entry" : "Edit Quick Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this quick entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let quickEntry { context.delete(quickEntry) }
                    context.saveAndRefresh()
                    Haptics.warning()
                    dismiss()
                }
            } message: {
                Text("Entries already logged with it stay.")
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                draft = start
                split = SplitMode.matching(share: start.partnerShare, amount: start.amount)
                customShare = start.partnerShare
            }
            .sensoryFeedback(.firmSelection, trigger: split) { _, _ in loaded }
        }
    }

    private func save() {
        guard canSave else { return }
        let target: QuickEntry
        if let quickEntry {
            target = quickEntry
        } else {
            target = QuickEntry(name: "", emoji: "", amount: 0, categoryID: nil,
                                sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1)
            context.insert(target)
        }
        let emoji = draft.emoji.trimmingCharacters(in: .whitespaces)
        target.name = draft.name.trimmingCharacters(in: .whitespaces)
        target.emoji = emoji.isEmpty ? (category?.emoji ?? "⭐️") : String(emoji.prefix(1))
        target.amount = draft.amount
        target.categoryID = draft.categoryID
        target.accountID = draft.accountID
        target.merchant = draft.merchant.trimmingCharacters(in: .whitespaces)
        target.partnerShare = partnerShare
        context.saveAndRefresh()
        Haptics.success()
        dismiss()
    }
}
