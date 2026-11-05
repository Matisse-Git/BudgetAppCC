import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @State private var search = ""
    @State private var editing: Entry?

    var body: some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        let days = grouped(filtered(lookup))
        NavigationStack {
            List {
                if days.isEmpty {
                    Text(search.isEmpty ? "No entries yet. Tap + on Home to add one." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(days, id: \.0) { day, items in
                    Section {
                        ForEach(items) { entry in
                            Button {
                                editing = entry
                            } label: {
                                EntryRow(entry: entry, lookup: lookup, partnerName: partnerName)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    context.delete(entry)
                                    context.saveAndRefresh()
                                }
                            }
                        }
                    } header: {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    }
                }
            }
            .searchable(text: $search, prompt: "Search notes, shops, categories, accounts")
            .navigationTitle("Transactions")
            .sheet(item: $editing) { entry in
                EntryEditorRouter(entry: entry)
            }
        }
    }

    private func filtered(_ lookup: Lookup) -> [Entry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = [
                entry.note,
                entry.merchant,
                entry.kind.label,
                lookup.category(entry.categoryID)?.name ?? "",
                lookup.accountName(entry.accountID),
                entry.toAccountID == nil ? "" : lookup.accountName(entry.toAccountID),
                String(entry.amount),
            ].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    private func grouped(_ items: [Entry]) -> [(Date, [Entry])] {
        let calendar = Calendar.kakeibo
        let groups = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.0 > $1.0 }
    }
}
