import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings (Settings artboard): privacy first, then logging, card bills, organising and data. Only
/// settings that do something are shown; payday months and week start are on the canvas but not built.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query private var quickEntries: [QuickEntry]
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @AppStorage(SettingsKey.setupDone) private var setupDone = true
    @AppStorage(SettingsKey.suggestCategory) private var suggests = true
    @AppStorage(SettingsKey.keypadHaptics) private var keypadHaptics = true
    @AppStorage(SettingsKey.eveningReminder) private var eveningReminder = false
    @AppStorage(SettingsKey.eveningReminderMinutes) private var eveningMinutes = 21 * 60
    @AppStorage(SettingsKey.billReminders) private var billReminders = true
    @AppStorage(SettingsKey.shortfallWarnings) private var shortfallWarnings = true
    @AppStorage(SettingsKey.faceIDLock) private var faceIDLock = false
    @AppStorage(SettingsKey.hideInSwitcher) private var hideInSwitcher = true
    @AppStorage(SettingsKey.lastBackup) private var lastBackup: Double = 0

    @State private var reorderingAccounts = false
    @State private var shareItem: ShareItem?
    @State private var importing = false
    @State private var pendingImport: Data?
    @State private var message: String?

    private var eveningTime: Binding<Date> {
        Binding(
            get: { Calendar.kakeibo.date(bySettingHour: eveningMinutes / 60, minute: eveningMinutes % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.kakeibo.dateComponents([.hour, .minute], from: date)
                eveningMinutes = (parts.hour ?? 21) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    SymbolTile(symbol: "lock.shield.fill", hue: .green, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On this iPhone only")
                            .font(.headline)
                        Text("No account and no bank connections. Your ledger never leaves this device.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.vertical, 6)
                HStack {
                    Text(lastBackup > 0 ? "Last backup \(Date(timeIntervalSince1970: lastBackup).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))" : "No backup yet")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button {
                        exportBackup()
                    } label: {
                        Text("Back Up Now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accentSoftText)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Capsule().fill(Palette.accentSoftFill))
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("General") {
                LabeledContent("Currency", value: "Japanese Yen (¥)")
                Picker("Default account", selection: $defaultAccountID) {
                    ForEach(accounts.filter { $0.tracksBalance && !$0.isArchived }) { account in
                        Text(account.name).tag(account.id.uuidString)
                    }
                }
                LabeledContent("Partner's name") {
                    TextField("Name", text: $partnerName)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Logging") {
                Toggle(isOn: $suggests) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Suggest category & account")
                        Text("Learns from time of day and your entries")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Toggle("Keypad haptics", isOn: $keypadHaptics)
                Toggle("Evening reminder", isOn: $eveningReminder)
                if eveningReminder {
                    DatePicker("Time", selection: eveningTime, displayedComponents: .hourAndMinute)
                }
            }

            Section {
                Toggle(isOn: $billReminders) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Bill reminders")
                        Text("3 days before each payment")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Toggle(isOn: $shortfallWarnings) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Shortfall warnings")
                        Text("When a bill closes, then 3 days and 1 day before")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                LabeledContent("Bank holidays", value: "Japan")
                Button("Allow notifications") {
                    BillNotifications.requestPermission()
                    Maintenance.run(context, autoPayoffs: false)
                }
            } header: {
                Text("Card bills")
            } footer: {
                Text("Payments that land on a weekend or a Japanese bank holiday move to the next business day; each card can change that.")
            }

            Section("Organize") {
                NavigationLink {
                    CategoriesView()
                } label: {
                    LabeledContent("Categories & budgets", value: "\(categories.filter { !$0.isArchived }.count)")
                }
                NavigationLink {
                    QuickEntriesView()
                } label: {
                    LabeledContent("Quick entries", value: "\(quickEntries.count)")
                }
                Button {
                    reorderingAccounts = true
                } label: {
                    LabeledContent("Accounts", value: "\(accounts.filter { !$0.isArchived }.count)")
                        .foregroundStyle(Palette.textPrimary)
                }
                Button("Show the welcome again") { setupDone = false }
            }

            Section {
                Toggle("Lock with Face ID", isOn: $faceIDLock)
                Toggle("Hide amounts in app switcher", isOn: $hideInSwitcher)
                Button {
                    exportBackup()
                } label: {
                    Label("Back Up to Files", systemImage: "square.and.arrow.up")
                }
                Button {
                    export { try Backup.exportCSV(context: context) }
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }
                Button {
                    importing = true
                } label: {
                    Label("Restore from Backup", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Privacy & data")
            } footer: {
                Text("Backups are files you keep in Files or iCloud Drive. Kakeibo has no servers and no account to sign in to.")
            }

            Section {
            } footer: {
                Text("Kakeibo \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .kScreenBackground()
        .navigationTitle("Settings")
        .onChange(of: eveningReminder) { _, on in
            if on { BillNotifications.requestPermission() }
            BillNotifications.scheduleEveningReminder()
        }
        .onChange(of: eveningMinutes) { _, _ in BillNotifications.scheduleEveningReminder() }
        .onChange(of: billReminders) { _, _ in Maintenance.run(context, autoPayoffs: false) }
        .onChange(of: shortfallWarnings) { _, _ in Maintenance.run(context, autoPayoffs: false) }
        .sensoryFeedback(.firmSelection, trigger: suggests)
        .sensoryFeedback(.firmSelection, trigger: keypadHaptics)
        .sensoryFeedback(.firmSelection, trigger: eveningReminder)
        .sensoryFeedback(.firmSelection, trigger: billReminders)
        .sensoryFeedback(.firmSelection, trigger: shortfallWarnings)
        .sensoryFeedback(.firmSelection, trigger: faceIDLock)
        .sensoryFeedback(.firmSelection, trigger: hideInSwitcher)
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

    private func exportBackup() {
        export {
            let url = try Backup.exportJSON(context: context)
            lastBackup = Date().timeIntervalSince1970
            return url
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
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 28)
            Text(category.name)
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
                            .sensoryFeedback(.firmSelection, trigger: archived)
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
