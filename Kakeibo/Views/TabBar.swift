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

/// The floating bar: four tabs in a glass capsule and the indigo + beside it, in thumb reach on every
/// screen. Tap + for a new expense; hold it for income, a transfer or a recent entry.
struct KakeiboTabBar: View {
    @Binding var selection: AppTab
    /// Recent entries offered when + is held, newest first.
    var recent: [Entry] = []
    var recentTitle: (Entry) -> String = { _ in "" }
    var onAdd: (EntryKind) -> Void
    var onRepeat: (Entry) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        if selection != tab { Haptics.selection() }
                        selection = tab
                    } label: {
                        item(tab)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                }
            }
            .padding(4)
            .frame(height: Metrics.tabBarHeight)
            .modifier(GlassBackground(shape: Capsule()))
            .shadow(color: .black.opacity(0.35), radius: 17, y: 10)

            addButton
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 2)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return VStack(spacing: 2) {
            Image(systemName: tab.symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(height: 24)
            Text(tab.title)
                .font(.kTabLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(selected ? Palette.accentTint : Palette.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(selected ? Palette.tabSelection : Color.clear))
        .contentShape(Capsule())
    }

    private var addButton: some View {
        Menu {
            Section {
                Button { onAdd(.expense) } label: { Label("Expense", systemImage: "minus.circle") }
                Button { onAdd(.income) } label: { Label("Income", systemImage: "plus.circle") }
                Button { onAdd(.transfer) } label: { Label("Transfer", systemImage: "arrow.left.arrow.right") }
            }
            if !recent.isEmpty {
                Section("Log again") {
                    ForEach(recent) { entry in
                        Button(recentTitle(entry)) { onRepeat(entry) }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Metrics.tabBarHeight, height: Metrics.tabBarHeight)
                .background(Circle().fill(Palette.accentFill))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 15, y: 10)
                .contentShape(Circle())
        } primaryAction: {
            onAdd(.expense)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Add transaction")
        .accessibilityHint("Hold for income, a transfer or a recent entry")
    }
}
