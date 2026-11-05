import SwiftData
import SwiftUI

struct HomeView: View {
    @Binding var showAdd: Bool

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @State private var monthOffset = 0

    private var monthDate: Date {
        Calendar.kakeibo.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    var body: some View {
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let interval = Ledger.monthInterval(containing: monthDate)
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 16) {
                        monthHeader
                        if monthOffset == 0 {
                            AttentionCard(entries: entries)
                            RemindersCard(reminders: Billing.reminders(ledger: ledger))
                        }
                        BudgetCard(ledger: ledger, categories: categories, interval: interval)
                        partnerCard(owed: ledger.partnerOwed)
                    }
                    .padding()
                    .padding(.bottom, 90)
                }
                .background(Color.groupedBackground)
                .simultaneousGesture(swipe)

                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Color.accentColor))
                        .shadow(radius: 4, y: 2)
                }
                .padding(20)
                .accessibilityLabel("Add entry")
            }
            .navigationTitle("Kakeibo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation { monthOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left").padding(8)
            }
            Spacer()
            Text(monthDate.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                withAnimation { monthOffset += 1 }
            } label: {
                Image(systemName: "chevron.right").padding(8)
            }
            .disabled(monthOffset >= 0)
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                withAnimation {
                    if value.translation.width < 0 {
                        if monthOffset < 0 { monthOffset += 1 }
                    } else {
                        monthOffset -= 1
                    }
                }
            }
    }

    private func partnerCard(owed: Int) -> some View {
        NavigationLink {
            PartnerView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill").font(.title2).foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    if owed > 0 {
                        Text("\(partnerName) owes you").font(.subheadline).foregroundStyle(.secondary)
                    } else if owed < 0 {
                        Text("\(partnerName) has paid back extra").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("\(partnerName): all settled").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(Yen.format(abs(owed))).font(.title2.bold()).monospacedDigit()
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

private struct AttentionCard: View {
    let entries: [Entry]

    var body: some View {
        let unconfirmed = entries.filter { $0.kind == .payoff && !$0.isConfirmed }.count
        let review = entries.filter { $0.needsReview }.count
        if unconfirmed + review > 0 {
            NavigationLink {
                ReviewListView()
            } label: {
                HStack {
                    Image(systemName: "checklist").foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        if unconfirmed > 0 {
                            Text("\(unconfirmed) payoff\(unconfirmed == 1 ? "" : "s") to confirm")
                        }
                        if review > 0 {
                            Text("\(review) logged entr\(review == 1 ? "y" : "ies") to review")
                        }
                    }
                    .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .cardStyle()
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RemindersCard: View {
    let reminders: [BillReminder]

    var body: some View {
        if !reminders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Upcoming bills").font(.headline)
                ForEach(reminders) { reminder in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(reminder.account.displayName)
                            Spacer()
                            Text(Yen.format(reminder.due)).monospacedDigit().bold()
                        }
                        Text(reminder.isOverdue
                             ? "Was due \(reminder.dueDate.formatted(.dateTime.day().month(.abbreviated)))"
                             : "Due \(reminder.dueDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                            .font(.caption)
                            .foregroundStyle(reminder.isOverdue ? Color.red : Color.secondary)
                        if reminder.shortfall > 0 {
                            Label("\(reminder.payFrom?.name ?? "Paying account") is \(Yen.format(reminder.shortfall)) short",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .cardStyle()
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(reminders.contains { $0.shortfall > 0 } ? Color.red : Color.clear, lineWidth: 2)
            )
        }
    }
}

private struct BudgetCard: View {
    let ledger: Ledger
    let categories: [BudgetCategory]
    let interval: DateInterval

    var body: some View {
        let spending = ledger.spendingByCategory(in: interval)
        let income = ledger.incomeByCategory(in: interval).values.reduce(0, +)
        let shown = categories.filter { $0.kind == .expense && (!$0.isArchived || (spending[$0.id] ?? 0) != 0) }
        let totalSpent = spending.values.reduce(0, +)
        let totalBudget = shown.filter { !$0.isArchived }.reduce(0) { $0 + $1.monthlyBudget }
        VStack(alignment: .leading, spacing: 12) {
            BudgetRow(title: "Spent this month", spent: totalSpent, budget: totalBudget, prominent: true)
            if income != 0 {
                HStack {
                    Text("Income")
                    Spacer()
                    Text(Yen.format(income, showPlus: true)).monospacedDigit().foregroundStyle(.green)
                }
                .font(.subheadline)
            }
            Divider()
            ForEach(shown) { category in
                BudgetRow(title: category.displayName, spent: spending[category.id] ?? 0,
                          budget: category.isArchived ? 0 : category.monthlyBudget, prominent: false)
            }
        }
        .cardStyle()
    }
}

private struct BudgetRow: View {
    let title: String
    let spent: Int
    let budget: Int
    let prominent: Bool

    private var isOver: Bool { budget > 0 && spent > budget }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(prominent ? .headline : .subheadline)
                Spacer()
                Text(budget > 0 ? "\(Yen.format(spent)) / \(Yen.format(budget))" : Yen.format(spent))
                    .font(prominent ? .headline : .subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isOver ? Color.red : Color.primary)
            }
            if budget > 0 {
                ProgressBar(fraction: Double(spent) / Double(budget), isOver: isOver)
                if prominent {
                    Text(isOver ? "\(Yen.format(spent - budget)) over budget" : "\(Yen.format(budget - spent)) left")
                        .font(.caption)
                        .foregroundStyle(isOver ? Color.red : Color.secondary)
                }
            }
        }
    }
}

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
                        HStack {
                            Button { editing = entry } label: { EntryRow(entry: entry, lookup: lookup) }
                                .buttonStyle(.plain)
                            Button {
                                entry.isConfirmed = true
                                context.saveAndRefresh()
                                Haptics.success()
                            } label: {
                                Image(systemName: "checkmark.circle").font(.title2)
                            }
                            .buttonStyle(.borderless)
                        }
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
                        Button { editing = entry } label: { EntryRow(entry: entry, lookup: lookup) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Looks right") {
                                    entry.needsReview = false
                                    context.saveAndRefresh()
                                }
                                .tint(.green)
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
