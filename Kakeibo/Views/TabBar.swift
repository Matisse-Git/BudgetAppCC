import Observation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case summary, activity, budgets, accounts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "Summary"
        case .activity: return "Activity"
        case .budgets: return "Budgets"
        case .accounts: return "Accounts"
        }
    }

    var symbol: String {
        switch self {
        case .summary: return "house"
        case .activity: return "list.bullet"
        case .budgets: return "chart.pie"
        case .accounts: return "creditcard"
        }
    }
}

/// What the + button does, handed down from RootView: open Quick Add with a draft, and the recent
/// expenses offered when + is held.
struct QuickAddAction {
    var start: (EntryDraft) -> Void = { _ in }
    var recent: [Entry] = []
    var title: (Entry) -> String = { _ in "" }
}

private struct QuickAddKey: EnvironmentKey {
    static let defaultValue = QuickAddAction()
}

extension EnvironmentValues {
    var quickAdd: QuickAddAction {
        get { self[QuickAddKey.self] }
        set { self[QuickAddKey.self] = newValue }
    }
}

/// The + in a tab's navigation bar. Tap for a new expense; hold for income, a transfer or a recent entry.
/// It lives in the navigation bar rather than on the tab bar, so the tab bar stays the system one.
struct AddEntryButton: View {
    @Environment(\.quickAdd) private var quickAdd

    var body: some View {
        Menu {
            Section {
                Button { quickAdd.start(EntryDraft(kind: .expense)) } label: { Label("Expense", systemImage: "minus.circle") }
                Button { quickAdd.start(EntryDraft(kind: .income)) } label: { Label("Income", systemImage: "plus.circle") }
                Button { quickAdd.start(EntryDraft(kind: .transfer)) } label: { Label("Transfer", systemImage: "arrow.left.arrow.right") }
            }
            if !quickAdd.recent.isEmpty {
                Section("Log again") {
                    ForEach(quickAdd.recent) { entry in
                        Button(quickAdd.title(entry)) {
                            quickAdd.start(EntryDraft(kind: .expense, amount: entry.amount, accountID: entry.accountID,
                                                      categoryID: entry.categoryID, note: entry.note, merchant: entry.merchant))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .fontWeight(.semibold)
        } primaryAction: {
            quickAdd.start(EntryDraft(kind: .expense))
        }
        .accessibilityLabel("Add transaction")
        .accessibilityHint("Hold for income, a transfer or a recent entry")
    }
}

/// On iOS 26 the tab bar shrinks while scrolling down, as the canvas asks.
struct MinimizeTabBarOnScroll: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

/// "Saved ¥980 · Dining Out · Wallet [Undo]": shown over the app for a few seconds after the add sheet
/// closes, so Save can close the sheet without losing Undo.
@MainActor
@Observable
final class SavedToastCenter {
    struct Item: Identifiable {
        let id = UUID()
        let message: String
        let entry: Entry
    }

    private(set) var current: Item?

    func show(_ message: String, entry: Entry) {
        let item = Item(message: message, entry: entry)
        withAnimation(.snappy) { current = item }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if self.current?.id == item.id {
                withAnimation(.easeOut) { self.current = nil }
            }
        }
    }

    /// Deletes the entry just saved.
    func undo(in context: ModelContext) {
        guard let item = current else { return }
        if item.entry.modelContext != nil && !item.entry.isDeleted {
            context.delete(item.entry)
            context.saveAndRefresh()
        }
        withAnimation(.easeOut) { current = nil }
        Haptics.selection()
    }
}
