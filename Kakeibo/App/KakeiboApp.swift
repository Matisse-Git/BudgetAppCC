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
        TabView(selection: $tab) {
            HomeView(showAdd: $showAdd)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet") }
                .tag(1)
            AccountsView()
                .tabItem { Label("Accounts", systemImage: "creditcard") }
                .tag(2)
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
}
