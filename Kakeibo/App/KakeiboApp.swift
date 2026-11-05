import SwiftData
import SwiftUI

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

    @State private var showAdd = false
    @State private var showSetup = false
    @State private var tab = 0

    var body: some View {
        if let screen = DemoMode.screen, DemoScreen.standalone.contains(screen) {
            DemoScreen(name: screen)
                .task { startDemo() }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeView(showAdd: $showAdd, tab: $tab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            TransactionsView()
                .tabItem { Label("Activity", systemImage: "list.bullet") }
                .tag(1)
            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "chart.pie") }
                .tag(2)
            AccountsView()
                .tabItem { Label("Accounts", systemImage: "creditcard") }
                .tag(3)
        }
        .sheet(isPresented: $showAdd) {
            EntryEditorView(mode: .new)
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
            if PendingAction.consumeAdd() { showAdd = true }
        }
        .onChange(of: setupDone) { _, done in
            if !done { showSetup = true }
        }
        .onOpenURL { url in
            if url.host == "add" { showAdd = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: PendingAction.notification)) { _ in
            if PendingAction.consumeAdd() { showAdd = true }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Maintenance.run(context)
                if PendingAction.consumeAdd() { showAdd = true }
            case .background:
                try? context.save()
            default:
                break
            }
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
        showAdd = screen == "add"
        let tabs = ["transactions": 1, "budgets": 2, "accounts": 3]
        tab = tabs[screen] ?? 0
        Maintenance.run(context, autoPayoffs: false)
    }
}
