import SwiftData
import SwiftUI
import UIKit

@main
struct KakeiboApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(AppData.shared.container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.setupDone) private var setupDone = false
    @AppStorage(SettingsKey.seeded) private var seeded = false
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""

    @State private var addDraft: EntryDraft?
    @Query(RootView.recentDescriptor) private var recentEntries: [Entry]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @State private var showSetup = false
    @State private var tab: AppTab = .summary
    @State private var keyboardShown = false

    var body: some View {
        if let screen = DemoMode.screen, DemoScreen.standalone.contains(screen) {
            DemoScreen(name: screen)
                .task { startDemo() }
        } else {
            tabs
        }
    }

    /// Every tab stays alive (keeping its navigation stack) and the floating bar sits on top, so it also
    /// shows on pushed screens as in the canvas.
    private var tabs: some View {
        ZStack {
            ForEach(AppTab.allCases) { item in
                tabContent(item)
                    .opacity(tab == item ? 1 : 0)
                    .allowsHitTesting(tab == item)
                    .accessibilityHidden(tab != item)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardShown {
                KakeiboTabBar(selection: $tab, recent: repeatable, recentTitle: repeatTitle, onAdd: { kind in
                    addDraft = EntryDraft(kind: kind)
                }, onRepeat: { entry in
                    addDraft = EntryDraft(kind: .expense, amount: entry.amount, accountID: entry.accountID,
                                          categoryID: entry.categoryID, note: entry.note, merchant: entry.merchant)
                })
            }
        }
        .tint(Palette.accentTint)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
        .sheet(item: $addDraft) { draft in
            EntryEditorView(mode: .new, draft: draft)
        }
        .fullScreenCover(isPresented: $showSetup) {
            SetupView {
                setupDone = true
                showSetup = false
            }
        }
        .task {
            if DemoMode.isOn {
                startDemo()
                return
            }
            if !seeded {
                if let id = Seed.insertDefaults(into: context), defaultAccountID.isEmpty {
                    defaultAccountID = id.uuidString
                }
                seeded = true
            }
            if !setupDone { showSetup = true }
            Maintenance.run(context)
            if PendingAction.consumeAdd() { addDraft = EntryDraft() }
        }
        .onChange(of: setupDone) { _, done in
            if !done { showSetup = true }
        }
        .onOpenURL { url in
            if url.host == "add" { addDraft = EntryDraft() }
        }
        .onReceive(NotificationCenter.default.publisher(for: PendingAction.notification)) { _ in
            if PendingAction.consumeAdd() { addDraft = EntryDraft() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Maintenance.run(context)
                if PendingAction.consumeAdd() { addDraft = EntryDraft() }
            case .background:
                try? context.save()
            default:
                break
            }
        }
    }

    static var recentDescriptor: FetchDescriptor<Entry> {
        var descriptor = FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 40
        return descriptor
    }

    /// The last few different expenses, offered when + is held.
    private var repeatable: [Entry] {
        let now = Date()
        var seen = Set<String>()
        var result: [Entry] = []
        for entry in recentEntries where entry.kind == .expense && !entry.isRefund && entry.date <= now {
            let key = "\(repeatTitle(entry))|\(entry.categoryID?.uuidString ?? "")"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(entry)
            if result.count == 3 { break }
        }
        return result
    }

    private func repeatTitle(_ entry: Entry) -> String {
        let label = entry.merchant.isEmpty ? entry.note : entry.merchant
        let name = label.isEmpty ? (categories.first { $0.id == entry.categoryID }?.name ?? "Expense") : label
        return "\(name) · \(Yen.format(entry.amount))"
    }

    @ViewBuilder
    private func tabContent(_ item: AppTab) -> some View {
        switch item {
        case .summary: SummaryView(tab: $tab)
        case .activity: TransactionsView()
        case .budgets: BudgetsView()
        case .accounts: AccountsView()
        }
    }

    /// Fills an in-memory database with sample data and opens the requested screen.
    private func startDemo() {
        guard (try? context.fetchCount(FetchDescriptor<Account>())) == 0 else { return }
        if let id = Seed.insertDefaults(into: context) { defaultAccountID = id.uuidString }
        DemoData.populate(context)
        let screen = DemoMode.screen ?? "home"
        setupDone = screen != "setup"
        showSetup = screen == "setup"
        if screen == "add" { addDraft = EntryDraft() }
        let tabs: [String: AppTab] = ["transactions": .activity, "budgets": .budgets, "budgets-all": .budgets,
                                      "accounts": .accounts, "accounts-flat": .accounts]
        tab = tabs[screen] ?? .summary
        Maintenance.run(context, autoPayoffs: false)
    }
}
