import Charts
import SwiftData
import SwiftUI

/// A bank, prepaid or cash account (Bank account artboard): balance, the last and next four weeks,
/// what's coming up with the balance after each, quick actions and history with a running balance.
struct BankAccountView: View {
    let account: Account

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @State private var editingAccount = false
    @State private var draft: EntryDraft?
    @State private var adjusting = false
    @State private var adjustText = ""

    var body: some View {
        let now = Date()
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let lookup = Lookup(accounts: accounts, categories: categories)
        let forecast = MoneyAccountForecast(account: account, ledger: ledger, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(forecast: forecast, ledger: ledger)
                if account.tracksBalance {
                    BalanceChartCard(forecast: forecast, hue: AccountLook.of(account).hue)
                        .padding(.top, 16)
                    upcoming(forecast, lookup: lookup)
                }
                actionTiles
                    .padding(.top, 16)
                history(ledger: ledger, lookup: lookup, now: now)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
        }
        .kScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editingAccount = true }
            }
        }
        .sheet(isPresented: $editingAccount) {
            AccountEditView(account: account)
        }
        .sheet(item: $draft) { draft in
            EntryEditorView(mode: .new, draft: draft)
        }
        .alert("Real balance", isPresented: $adjusting) {
            TextField("¥", text: $adjustText)
                .keyboardType(.numbersAndPunctuation)
            Button("Save") { applyAdjustment(ledger: ledger) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The difference is saved as an adjustment. It never counts as spending.")
        }
    }

    // MARK: Sections

    private func header(forecast: MoneyAccountForecast, ledger: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AccountIcon(account: account, size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.name)
                        .font(.title2.bold())
                        .foregroundStyle(Palette.textPrimary)
                    Text(subtitle(ledger: ledger))
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            if account.tracksBalance {
                Text(Yen.format(forecast.today))
                    .font(.kDetailAmount)
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(forecast.today < 0 ? Palette.negativeText : Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 10)
                Text("Balance today")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Text("Top-ups to this account count as spending, so it has no balance.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 10)
            }
        }
    }

    private func subtitle(ledger: Ledger) -> String {
        let kind: String
        switch account.kind {
        case .bank: kind = "Bank account"
        case .topUp: kind = "Prepaid wallet"
        case .cash: kind = "Cash"
        case .credit: kind = "Credit card"
        }
        let cards = ledger.accounts.filter { $0.kind == .credit && !$0.isArchived && $0.payFromAccountID == account.id }
        return cards.isEmpty ? kind : "\(kind) · pays \(AccountText.list(cards.map(\.name)))"
    }

    @ViewBuilder
    private func upcoming(_ forecast: MoneyAccountForecast, lookup: Lookup) -> some View {
        if !forecast.upcoming.isEmpty {
            SectionCaps(title: "Upcoming", trailing: "Balance after")
                .padding(.top, Metrics.sectionSpacing)
            CardList {
                ForEach(Array(forecast.upcoming.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { ListDivider(inset: 68) }
                    UpcomingRow(item: item, lookup: lookup, partnerName: partnerName)
                }
                if forecast.paysBills {
                    ListDivider(inset: 16)
                    coverage(forecast)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func coverage(_ forecast: MoneyAccountForecast) -> some View {
        Group {
            if let short = forecast.firstShortBill {
                Label("\(Yen.format(-short.balanceAfter)) short on \(short.date.formatted(.dateTime.month(.abbreviated).day()))",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
            } else {
                Label("Covers every upcoming bill", systemImage: "checkmark")
                    .foregroundStyle(Palette.positive)
            }
        }
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var actionTiles: some View {
        HStack(spacing: 10) {
            ActionTile(title: "Transfer", symbol: "arrow.left.arrow.right") {
                draft = EntryDraft(kind: .transfer, accountID: account.id)
            }
            if account.tracksBalance {
                ActionTile(title: "Adjust balance", symbol: "slider.horizontal.3") {
                    adjustText = String(Ledger(accounts: accounts, entries: entries).balance(of: account, before: Date()))
                    adjusting = true
                }
            }
            ActionTile(title: "Add entry", symbol: "plus") {
                draft = EntryDraft(kind: .expense, accountID: account.id)
            }
        }
    }

    @ViewBuilder
    private func history(ledger: Ledger, lookup: Lookup, now: Date) -> some View {
        let rows = AccountHistory.rows(for: account, ledger: ledger, now: now)
        SectionCaps(title: "History", trailing: account.tracksBalance ? "Running balance" : nil)
            .padding(.top, Metrics.sectionSpacing)
        if rows.isEmpty {
            Text("No entries yet.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .kCard()
                .padding(.top, 8)
        } else {
            CardList {
                ForEach(Array(rows.prefix(6).enumerated()), id: \.element.entry.id) { index, row in
                    if index > 0 { ListDivider() }
                    NavigationLink {
                        TransactionDetailView(entry: row.entry)
                    } label: {
                        HistoryRow(row: row, lookup: lookup, partnerName: partnerName, showsBalance: account.tracksBalance)
                    }
                    .buttonStyle(.plain)
                }
                if rows.count > 6 {
                    ListDivider(inset: 16)
                    NavigationLink {
                        AccountHistoryView(account: account)
                    } label: {
                        HStack {
                            Text("Show all history").foregroundStyle(Palette.accentTint)
                            Spacer()
                            Chevron()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: Metrics.compactRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }

    private func applyAdjustment(ledger: Ledger) {
        guard let real = Yen.parse(adjustText) else { return }
        let delta = real - ledger.balance(of: account, before: Date())
        guard delta != 0 else { return }
        context.insert(Entry(kind: .adjust, amount: delta, date: Date(), accountID: account.id))
        context.saveAndRefresh()
        Haptics.success()
    }
}

// MARK: - History

/// An entry on an account's history with the balance right after it.
struct HistoryLine {
    let entry: Entry
    /// Signed change to this account.
    let change: Int
    let balanceAfter: Int
}

enum AccountHistory {
    /// Entries that touched the account up to `now`, newest first, each with the balance after it.
    static func rows(for account: Account, ledger: Ledger, now: Date = Date()) -> [HistoryLine] {
        let touching = ledger.entries
            .filter { $0.date <= now && Ledger.effect(of: $0, on: account.id) != 0 }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        var running = account.openingBalance
        var lines: [HistoryLine] = []
        for entry in touching {
            let change = Ledger.effect(of: entry, on: account.id)
            running += change
            lines.append(HistoryLine(entry: entry, change: change, balanceAfter: running))
        }
        return lines.reversed()
    }
}

/// History row: what, when, the signed change with a true minus, and the balance after.
struct HistoryRow: View {
    let row: HistoryLine
    let lookup: Lookup
    var partnerName = SettingsKey.defaultPartnerName
    var showsBalance = true

    var body: some View {
        let look = EntryPresentation(entry: row.entry, lookup: lookup, partnerName: partnerName)
        KRow(look.title) {
            look.icon()
        } subtitle: {
            HStack(spacing: 6) {
                Text(detail(look))
                if row.entry.kind == .payoff && row.entry.isAutoCreated { AutoBadge() }
            }
        } trailing: {
            AmountStack(Yen.format(row.change, showPlus: row.change > 0),
                        color: row.change > 0 ? Palette.positive : Palette.textPrimary,
                        caption: showsBalance ? Yen.format(row.balanceAfter) : nil)
        }
    }

    private func detail(_ look: EntryPresentation) -> String {
        let date = row.entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        switch row.entry.kind {
        case .transfer:
            let other = row.change < 0 ? look.toAccount : look.account
            return "\(date) · \(row.change < 0 ? "to" : "from") \(other?.name ?? "another account")"
        case .expense, .income:
            if look.usesCategoryAsTitle { return date }
            return "\(date) · \(look.category?.name ?? "Uncategorised")"
        default:
            return date
        }
    }
}

/// Every entry on an account.
struct AccountHistoryView: View {
    let account: Account
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName

    var body: some View {
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let lookup = Lookup(accounts: accounts, categories: categories)
        let rows = AccountHistory.rows(for: account, ledger: ledger)
        List(rows, id: \.entry.id) { row in
            HistoryRow(row: row, lookup: lookup, partnerName: partnerName, showsBalance: account.tracksBalance)
                .background {
                    NavigationLink {
                        TransactionDetailView(entry: row.entry)
                    } label: {
                        EmptyView()
                    }
                    .opacity(0)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .kScreenBackground()
        .navigationTitle(account.name)
    }
}

// MARK: - Pieces

/// "NOV / 25" date tile, a title and the change with the balance after (Upcoming list).
struct UpcomingRow: View {
    let item: UpcomingItem
    let lookup: Lookup
    var partnerName = SettingsKey.defaultPartnerName

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(item.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(0.4)
                    .foregroundStyle(Palette.accentSoftText)
                Text(item.date.formatted(.dateTime.day()))
                    .font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(width: 40, height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.chipFill))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AmountStack(Yen.format(item.amount, showPlus: item.amount > 0),
                        color: item.amount > 0 ? Palette.positive : Palette.textPrimary,
                        caption: Yen.format(item.balanceAfter))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch item.source {
        case .entry(let entry): return EntryPresentation(entry: entry, lookup: lookup, partnerName: partnerName).title
        case .bill(let bill): return "\(bill.account.name) bill"
        }
    }

    private var detail: String {
        switch item.source {
        case .entry: return "Scheduled"
        case .bill(let bill): return "\(BillingText.period(bill.cycle)) statement"
        }
    }
}

/// One of the square quick actions on an account page.
struct ActionTile: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Palette.accentTint)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The last four weeks of balance and the next four projected with dated entries and card bills.
struct BalanceChartCard: View {
    let forecast: MoneyAccountForecast
    var hue: Hue = .blue

    private struct Point: Identifiable {
        let date: Date
        let balance: Int
        let series: String
        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
    }

    var body: some View {
        let points = forecast.past.map { Point(date: $0.date, balance: $0.balance, series: "Balance") }
            + forecast.future.map { Point(date: $0.date, balance: $0.balance, series: "Projected") }
        let today = Calendar.kakeibo.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Balance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("Past 4 weeks · next 4 weeks")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Balance", point.balance),
                        series: .value("Series", point.series)
                    )
                    .foregroundStyle(hue.color)
                    .lineStyle(point.series == "Projected"
                               ? StrokeStyle(lineWidth: 2, dash: [4, 4])
                               : StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.stepEnd)
                }
                RuleMark(x: .value("Today", today))
                    .foregroundStyle(Palette.textPrimary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .bottom, alignment: .center) {
                        Text("Today")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(Palette.separator)
                    AxisValueLabel {
                        if let yen = value.as(Int.self) { Text(yen == 0 ? "¥0" : Yen.short(yen)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 150)
            .accessibilityLabel("Balance \(Yen.format(forecast.today)) today, projected \(Yen.format(forecast.future.last?.balance ?? forecast.today)) in four weeks")
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Capsule().fill(hue.color).frame(width: 16, height: 3)
                    Text("Balance")
                }
                HStack(spacing: 6) {
                    Capsule().stroke(hue.color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 16, height: 2)
                    Text("With scheduled items & card bills")
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.textSecondary)
            .accessibilityHidden(true)
        }
        .kCard()
    }
}
