import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @AppStorage(SettingsKey.setupDone) private var setupDone = true
    @AppStorage(SettingsKey.groupAccountsByType) private var groupAccountsByType = false
    @State private var reorderingAccounts = false

    @State private var shareItem: ShareItem?
    @State private var importing = false
    @State private var pendingImport: Data?
    @State private var message: String?

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default account", selection: $defaultAccountID) {
                    ForEach(accounts.filter { $0.tracksBalance && !$0.isArchived }) { account in
                        Text(account.displayName).tag(account.id.uuidString)
                    }
                }
                HStack {
                    Text("Partner's name")
                    Spacer()
                    TextField("Name", text: $partnerName).multilineTextAlignment(.trailing)
                }
            }
            Section {
                Toggle("Group accounts by type", isOn: $groupAccountsByType)
                    .sensoryFeedback(.selection, trigger: groupAccountsByType)
                Button("Reorder accounts…") { reorderingAccounts = true }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Grouping splits the Accounts tab into Bank, Top-up and Cash. Credit cards always show as cards.")
            }
            Section("Manage") {
                NavigationLink("Categories & budgets") { CategoriesView() }
                Button("Run setup checklist again") { setupDone = false }
            }
            Section {
                Button("Enable bill notifications") {
                    BillNotifications.requestPermission()
                    Maintenance.run(context, autoPayoffs: false)
                }
            } footer: {
                Text("You'll get a notification 3 days and 1 day before a card bill the paying account can't cover.")
            }
            Section {
                Button("Export full backup (JSON)") { export { try Backup.exportJSON(context: context) } }
                Button("Export transactions (CSV)") { export { try Backup.exportCSV(context: context) } }
                Button("Restore from backup…") { importing = true }
            } header: {
                Text("Data")
            } footer: {
                Text("Your data lives only on this phone. Save a JSON backup to Files now and then, especially before changing how the app is installed.")
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $reorderingAccounts) {
            ReorderAccountsView()
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    pendingImport = data
                } else {
                    message = "Couldn't read that file."
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Replace all data?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Replace", role: .destructive) {
                if let data = pendingImport {
                    do {
                        try Backup.restore(from: data, into: context)
                        Maintenance.run(context, autoPayoffs: false)
                        message = "Backup restored."
                        Haptics.success()
                    } catch {
                        message = "Restore failed: \(error.localizedDescription)"
                    }
                }
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Everything currently in Kakeibo will be replaced by the backup.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func export(_ make: () throws -> URL) {
        do {
            shareItem = ShareItem(url: try make())
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }
}

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @State private var kind: CategoryKind = .expense
    @State private var editing: BudgetCategory?
    @State private var creating = false

    private var active: [BudgetCategory] { categories.filter { $0.kind == kind && !$0.isArchived } }
    private var archived: [BudgetCategory] { categories.filter { $0.kind == kind && $0.isArchived } }

    var body: some View {
        List {
            Picker("Kind", selection: $kind) {
                ForEach(CategoryKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Section {
                ForEach(active) { category in
                    Button {
                        editing = category
                    } label: {
                        row(category)
                    }
                    .buttonStyle(.plain)
                }
                .onMove(perform: move)
            } footer: {
                if kind == .expense {
                    Text("Total monthly budget: \(Yen.format(active.reduce(0) { $0 + $1.monthlyBudget }))")
                }
            }
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { category in
                        Button {
                            editing = category
                        } label: {
                            row(category).opacity(0.6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { category in
            CategoryEditView(category: category, kind: category.kind)
        }
        .sheet(isPresented: $creating) {
            CategoryEditView(category: nil, kind: kind)
        }
    }

    private func row(_ category: BudgetCategory) -> some View {
        HStack {
            Text(category.displayName)
            Spacer()
            if category.kind == .expense {
                Text(category.monthlyBudget > 0 ? Yen.format(category.monthlyBudget) : "No budget")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }

    private func move(from source: IndexSet, to destination: Int) {
        var items = active
        items.move(fromOffsets: source, toOffset: destination)
        for (index, category) in items.enumerated() {
            category.sortOrder = index + (kind == .income ? 100 : 0)
        }
        try? context.save()
        Haptics.lift()
    }
}

struct CategoryEditView: View {
    let category: BudgetCategory?
    let kind: CategoryKind

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BudgetCategory.sortOrder) private var all: [BudgetCategory]

    @State private var name = ""
    @State private var emoji = ""
    @State private var budget = 0
    @State private var archived = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Emoji", text: $emoji)
                }
                if kind == .expense {
                    Section {
                        AmountField(title: "Monthly budget", value: $budget)
                    } footer: {
                        Text("Leave at ¥0 for no budget. Spending still shows.")
                    }
                }
                if category != nil {
                    Section {
                        Toggle("Archived", isOn: $archived)
                            .sensoryFeedback(.selection, trigger: archived)
                    } footer: {
                        Text("Archived categories disappear from the add screen but keep their history.")
                    }
                }
            }
            .navigationTitle(category == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let category {
                    name = category.name
                    emoji = category.emoji
                    budget = category.monthlyBudget
                    archived = category.isArchived
                }
            }
        }
    }

    private func save() {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        let target: BudgetCategory
        if let category {
            target = category
        } else {
            target = BudgetCategory(name: name, emoji: "📦", kind: kind, sortOrder: (all.map(\.sortOrder).max() ?? 0) + 1)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.emoji = trimmedEmoji.isEmpty ? "📦" : String(trimmedEmoji.prefix(1))
        target.monthlyBudget = kind == .expense ? max(budget, 0) : 0
        target.isArchived = archived
        context.saveAndRefresh()
        dismiss()
    }
}
