import SwiftData
import SwiftUI

/// The Activity tab: search, type/account/category filters, months with what was spent, days with
/// their totals, and card statements closing in between. Swipe a row to duplicate or delete it.
struct TransactionsView: View {
    enum TypeFilter: String, CaseIterable, Identifiable {
        case all, expenses, income, transfers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .expenses: return "Expenses"
            case .income: return "Income"
            case .transfers: return "Transfers"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @State private var search = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var accountFilter: UUID?
    @State private var categoryFilter: UUID?

    var body: some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        let months = sections(lookup: lookup)
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Group {
                        searchField
                        filterChips
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if months.isEmpty {
                        Text(isFiltering ? "No matches." : "No entries yet. Tap + to add one.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(months) { month in
                        monthHeader(month)
                            .id(month.id)
                            .listRowInsets(EdgeInsets(top: 18, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        ForEach(month.days) { day in
                            Section {
                                ForEach(day.items) { item in
                                    row(item, lookup: lookup)
                                }
                            } header: {
                                SectionCaps(title: dayTitle(day.date), trailing: day.spent > 0 ? Yen.format(day.spent) : nil, inset: 4)
                                    .textCase(nil)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(16)
                .scrollContentBackground(.hidden)
                .kScreenBackground()
                .navigationTitle("Activity")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ForEach(months) { month in
                                Button(month.title) {
                                    withAnimation { proxy.scrollTo(month.id, anchor: .top) }
                                }
                            }
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .accessibilityLabel("Jump to month")
                        .disabled(months.isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        AddEntryButton()
                    }
                }
            }
        }
    }

    // MARK: Header pieces

    private var isFiltering: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty || typeFilter != .all || accountFilter != nil || categoryFilter != nil
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            TextField("Notes, categories, amounts", text: $search)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .foregroundStyle(Palette.textPrimary)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Capsule().fill(Palette.controlFill))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TypeFilter.allCases) { filter in
                    Button {
                        typeFilter = filter
                        Haptics.selection()
                    } label: {
                        FilterChip(title: filter.title, selected: typeFilter == filter)
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    Button("Any account") { accountFilter = nil }
                    ForEach(AccountLayout.sorted(accounts.filter { !$0.isArchived })) { account in
                        Button(account.name) { accountFilter = account.id }
                    }
                } label: {
                    FilterChip(title: accounts.first { $0.id == accountFilter }?.name ?? "Account",
                               selected: accountFilter != nil, menu: true)
                }
                Menu {
                    Button("Any category") { categoryFilter = nil }
                    ForEach(categories.filter { !$0.isArchived }) { category in
                        Button(category.name) { categoryFilter = category.id }
                    }
                } label: {
                    FilterChip(title: categories.first { $0.id == categoryFilter }?.name ?? "Category",
                               selected: categoryFilter != nil, menu: true)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func monthHeader(_ month: MonthSection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.title)
                .font(.title3.bold())
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(month.summary)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.kakeibo
        let full = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if calendar.isDateInToday(date) { return "Today · \(full)" }
        if calendar.isDateInYesterday(date) { return "Yesterday · \(full)" }
        return full
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ item: FeedItem, lookup: Lookup) -> some View {
        switch item {
        case .entry(let entry):
            TransactionRow(entry: entry, lookup: lookup, partnerName: partnerName, timeStyle: .time)
                .background {
                    // A hidden link keeps the row free of the list's disclosure chevron, as on the canvas.
                    NavigationLink {
                        TransactionDetailView(entry: entry)
                    } label: {
                        EmptyView()
                    }
                    .opacity(0)
                }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.card)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    delete(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    duplicate(entry)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .tint(Palette.accentFill)
            }
            .contextMenu {
                Button {
                    duplicate(entry)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    delete(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        case .statement(let event):
            StatementClosedRow(event: event, payer: lookup.accounts[event.account.payFromAccountID ?? UUID()])
                .background {
                    NavigationLink {
                        AccountDetailView(account: event.account)
                    } label: {
                        EmptyView()
                    }
                    .opacity(0)
                }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.card)
        }
    }

    private func delete(_ entry: Entry) {
        context.delete(entry)
        context.saveAndRefresh()
        Haptics.warning()
    }

    private func duplicate(_ entry: Entry) {
        let copy = Entry(kind: entry.kind, amount: entry.amount, date: Date(), accountID: entry.accountID,
                         toAccountID: entry.toAccountID, categoryID: entry.categoryID)
        copy.note = entry.note
        copy.merchant = entry.merchant
        copy.isRefund = entry.isRefund
        copy.partnerShare = entry.partnerShare
        context.insert(copy)
        context.saveAndRefresh()
        Haptics.success()
    }

    // MARK: Building the feed

    private func matches(_ entry: Entry, query: String, lookup: Lookup) -> Bool {
        switch typeFilter {
        case .all: break
        case .expenses: guard entry.kind == .expense else { return false }
        case .income: guard entry.kind == .income || entry.kind == .settlement else { return false }
        case .transfers: guard entry.kind == .transfer || entry.kind == .payoff else { return false }
        }
        if let accountFilter, entry.accountID != accountFilter, entry.toAccountID != accountFilter { return false }
        if let categoryFilter, entry.categoryID != categoryFilter { return false }
        guard !query.isEmpty else { return true }
        let haystack = [
            entry.note,
            entry.merchant,
            entry.kind.label,
            lookup.category(entry.categoryID)?.name ?? "",
            lookup.accountName(entry.accountID),
            entry.toAccountID == nil ? "" : lookup.accountName(entry.toAccountID),
            String(entry.amount),
            Yen.format(entry.amount),
        ].joined(separator: " ").lowercased()
        return haystack.contains(query)
    }

    private func sections(lookup: Lookup) -> [MonthSection] {
        let calendar = Calendar.kakeibo
        let now = Date()
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = entries.filter { $0.date <= now && matches($0, query: query, lookup: lookup) }
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        // Unfiltered, a month's total is what it counted, installment slices included.
        let unfiltered = query.isEmpty && accountFilter == nil && categoryFilter == nil && typeFilter != .income && typeFilter != .transfers
        var items: [FeedItem] = shown.map { .entry($0) }

        // Statements closing, when nothing narrows the list (or it's narrowed to that card).
        let showsStatements = query.isEmpty && categoryFilter == nil && (typeFilter == .all || typeFilter == .transfers)
        if showsStatements, let oldest = entries.last?.date {
            for event in Billing.closedStatements(ledger: ledger, from: oldest, to: now, calendar: calendar)
            where accountFilter == nil || accountFilter == event.account.id {
                items.append(.statement(event))
            }
        }

        let byMonth = Dictionary(grouping: items) { Ledger.monthInterval(containing: $0.date, calendar: calendar).start }
        return byMonth.keys.sorted(by: >).map { monthStart in
            let monthItems = byMonth[monthStart] ?? []
            let byDay = Dictionary(grouping: monthItems) { calendar.startOfDay(for: $0.date) }
            let days = byDay.keys.sorted(by: >).map { day in
                DaySection(date: day, items: (byDay[day] ?? []).sorted { $0.date > $1.date })
            }
            return MonthSection(start: monthStart, days: days, filter: typeFilter,
                                ledgerSpent: unfiltered ? ledger.totalSpending(in: Ledger.monthInterval(containing: monthStart, calendar: calendar)) : nil)
        }
    }
}

// MARK: - Feed model

private enum FeedItem: Identifiable {
    case entry(Entry)
    case statement(StatementEvent)

    var id: String {
        switch self {
        case .entry(let entry): return entry.id.uuidString
        case .statement(let event): return "statement-\(event.id)"
        }
    }

    /// Statements sort at the end of their closing day.
    var date: Date {
        switch self {
        case .entry(let entry): return entry.date
        case .statement(let event): return event.cycle.closingBoundary.addingTimeInterval(-1)
        }
    }

    var entry: Entry? {
        if case .entry(let entry) = self { return entry }
        return nil
    }
}

private struct DaySection: Identifiable {
    let date: Date
    let items: [FeedItem]
    var id: Date { date }

    /// My spending that day.
    var spent: Int {
        items.compactMap(\.entry)
            .filter { $0.kind == .expense && !($0.isInstallment && $0.installmentMode != .all) }
            .reduce(0) { $0 + ($1.isRefund ? -$1.amount : $1.myShare) }
    }
}

private struct MonthSection: Identifiable {
    let start: Date
    let days: [DaySection]
    let filter: TransactionsView.TypeFilter
    var ledgerSpent: Int? = nil
    var id: Date { start }

    var title: String {
        let sameYear = Calendar.kakeibo.isDate(start, equalTo: Date(), toGranularity: .year)
        return sameYear ? start.formatted(.dateTime.month(.wide)) : start.formatted(.dateTime.month(.wide).year())
    }

    var summary: String {
        let entries = days.flatMap(\.items).compactMap(\.entry)
        switch filter {
        case .income:
            return "\(Yen.format(entries.reduce(0) { $0 + $1.amount })) in"
        case .transfers:
            return entries.count == 1 ? "1 transfer" : "\(entries.count) transfers"
        case .all, .expenses:
            return "\(Yen.format(ledgerSpent ?? days.reduce(0) { $0 + $1.spent })) spent"
        }
    }
}

// MARK: - Pieces

/// A filter in the Activity chip row: white when selected.
struct FilterChip: View {
    let title: String
    let selected: Bool
    var menu = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            if menu {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
        }
        .font(.subheadline.weight(selected ? .semibold : .medium))
        .foregroundStyle(selected ? Palette.background : Palette.textPrimary)
        .padding(.leading, 14)
        .padding(.trailing, menu ? 10 : 14)
        .frame(height: 34)
        .background(Capsule().fill(selected ? Palette.textPrimary : Palette.controlFill))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// "Travel Card statement closed · ¥58,900 due Thu, Dec 10 · Main Bank".
struct StatementClosedRow: View {
    let event: StatementEvent
    let payer: Account?

    var body: some View {
        let color = AccountLook.cardColor(event.account)
        KRow("\(event.account.name) statement closed", subtitle: subtitle, chevron: true) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color.bright)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.color.opacity(0.35)))
                .accessibilityHidden(true)
        } trailing: {
            EmptyView()
        }
    }

    private var subtitle: String {
        let date = event.cycle.paymentDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let base = "\(Yen.format(event.amount)) due \(date)"
        return payer.map { "\(base) · \($0.name)" } ?? base
    }
}
