import Foundation

/// A titled run of accounts on the Accounts tab.
struct AccountGroup: Identifiable {
    let id: String
    let title: String
    let accounts: [Account]
}

/// The order and grouping of the Accounts tab. One custom order (`Account.sortOrder`) is shared by
/// every view: grouping by type only splits the list, it never changes who comes first within a type.
enum AccountLayout {
    /// The types the "Group by type" setting splits non-credit accounts into, in this order.
    static let moneyKinds: [AccountKind] = [.bank, .topUp, .cash]

    /// Custom order; ties (older data) fall back to creation date.
    static func sorted(_ accounts: [Account]) -> [Account] {
        accounts.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    /// Active credit accounts, drawn as cards.
    static func cards(_ accounts: [Account]) -> [Account] {
        sorted(accounts.filter { !$0.isArchived && $0.kind == .credit })
    }

    /// Active non-credit accounts: one "Money" list, or one list per type.
    static func moneyGroups(_ accounts: [Account], byType: Bool) -> [AccountGroup] {
        let money = sorted(accounts.filter { !$0.isArchived && $0.kind != .credit })
        guard byType else {
            return money.isEmpty ? [] : [AccountGroup(id: "money", title: "Money", accounts: money)]
        }
        return moneyKinds.compactMap { kind in
            let items = money.filter { $0.kind == kind }
            return items.isEmpty ? nil : AccountGroup(id: kind.rawValue, title: kind.label, accounts: items)
        }
    }

    /// The lists shown when reordering: credit cards first, then the money list(s).
    static func editGroups(_ accounts: [Account], byType: Bool) -> [AccountGroup] {
        let cards = cards(accounts)
        let cardGroup = cards.isEmpty ? [] : [AccountGroup(id: "cards", title: "Credit cards", accounts: cards)]
        return cardGroup + moneyGroups(accounts, byType: byType)
    }

    /// Moves rows within one group, then renumbers every account to match what's on screen.
    static func move(group index: Int, from source: IndexSet, to destination: Int, in groups: [AccountGroup], all: [Account]) {
        guard groups.indices.contains(index) else { return }
        var lists = groups.map(\.accounts)
        lists[index].move(fromOffsets: source, toOffset: destination)
        applyOrder(lists.flatMap { $0 }, all: all)
    }

    /// Writes `sortOrder` so `ordered` comes first in exactly this order; everything else (archived
    /// accounts) follows in its existing order.
    static func applyOrder(_ ordered: [Account], all: [Account]) {
        let ids = Set(ordered.map(\.id))
        let rest = sorted(all.filter { !ids.contains($0.id) })
        for (index, account) in (ordered + rest).enumerated() where account.sortOrder != index {
            account.sortOrder = index
        }
    }

    /// Sort order for a new account: last, so it appears at the bottom of its list.
    static func nextSortOrder(_ accounts: [Account]) -> Int {
        (accounts.map(\.sortOrder).max() ?? -1) + 1
    }
}
