import SwiftData
import SwiftUI

/// Unconfirmed payoffs and entries logged from Shortcuts.
struct ReviewListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @State private var editing: Entry?

    var body: some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        let payoffs = entries.filter { $0.kind == .payoff && !$0.isConfirmed }
        let review = entries.filter { $0.needsReview }
        List {
            if !payoffs.isEmpty {
                Section {
                    ForEach(payoffs) { entry in
                        HStack(spacing: 0) {
                            Button { editing = entry } label: { TransactionRow(entry: entry, lookup: lookup, timeStyle: .relative) }
                                .buttonStyle(.plain)
                            Button {
                                entry.isConfirmed = true
                                context.saveAndRefresh()
                                Haptics.success()
                            } label: {
                                Image(systemName: "checkmark.circle").font(.title2)
                            }
                            .buttonStyle(.borderless)
                            .padding(.trailing, 16)
                            .accessibilityLabel("Confirm payoff")
                        }
                        .listRowInsets(EdgeInsets())
                    }
                } header: {
                    Text("Payoffs to confirm")
                } footer: {
                    Text("Tick once you've seen the debit in your bank. Tap to fix the amount.")
                }
            }
            if !review.isEmpty {
                Section("Logged automatically") {
                    ForEach(review) { entry in
                        Button { editing = entry } label: { TransactionRow(entry: entry, lookup: lookup, timeStyle: .relative) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets())
                            .swipeActions {
                                Button("Looks right") {
                                    entry.needsReview = false
                                    context.saveAndRefresh()
                                    Haptics.success()
                                }
                                .tint(Palette.positive)
                            }
                    }
                }
            }
            if payoffs.isEmpty && review.isEmpty {
                Text("Nothing to review.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("To review")
        .sheet(item: $editing) { entry in
            EntryEditorRouter(entry: entry)
        }
    }
}
