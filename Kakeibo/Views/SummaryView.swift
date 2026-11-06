import SwiftData
import SwiftUI

/// The Summary tab (Main artboard): a card bill the paying account won't cover, this month's budget
/// against today's pace, the categories that need a look, upcoming card bills and the latest entries.
struct SummaryView: View {
    @Binding var tab: AppTab

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @AppStorage(SettingsKey.shortfallWarnings) private var shortfallWarnings = true
    @State private var draft: EntryDraft?
    @State private var editing: Entry?

    var body: some View {
        let now = Date()
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let pace = BudgetPace(ledger: ledger, month: now, now: now)
        let bills = Billing.reminders(ledger: ledger, now: now)
        let warning = shortfallWarnings ? bills.first(where: { $0.shortfall > 0 }) : nil
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(now)
                    if let warning {
                        ShortfallCard(reminder: warning) { startTransfer(for: warning, ledger: ledger, now: now) }
                            .padding(.top, 16)
                    }
                    BudgetHeroCard(pace: pace) { tab = .budgets }
                        .padding(.top, warning == nil ? 16 : 12)
                    attentionSection(pace)
                    billsSection(bills, ledger: ledger, now: now)
                    toDoSection(ledger)
                    recentSection(now: now)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 24)
            }
            .kScreenBackground()
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The title is drawn in the content, under the date.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $draft) { draft in
                EntryEditorView(mode: .new, draft: draft)
            }
            .sheet(item: $editing) { entry in
                EntryEditorRouter(entry: entry)
            }
        }
    }

    // MARK: Sections

    private func header(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.kSectionCaps)
                .kerning(0.2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textSecondary)
            Text("Summary")
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func attentionSection(_ pace: BudgetPace) -> some View {
        let items = Array(pace.needsAttention.prefix(3))
        if !items.isEmpty {
            SectionTitle("Needs attention") {
                Button("Budgets") { tab = .budgets }
            }
            .padding(.top, Metrics.sectionSpacing)
            CardList {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { ListDivider() }
                    Button {
                        tab = .budgets
                    } label: {
                        AttentionRow(item: item, monthStart: pace.interval.start)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func billsSection(_ bills: [BillReminder], ledger: Ledger, now: Date) -> some View {
        let cards = AccountLayout.cards(accounts)
        if !cards.isEmpty {
            let building = cards.reduce(0) { $0 + Billing.status(for: $1, ledger: ledger, now: now).nextSoFar }
            SectionTitle("Upcoming card bills") {
                Button("Accounts") { tab = .accounts }
            }
            .padding(.top, Metrics.sectionSpacing)
            CardList {
                ForEach(bills) { bill in
                    NavigationLink {
                        AccountDetailView(account: bill.account)
                    } label: {
                        BillRow(reminder: bill, warns: shortfallWarnings)
                    }
                    .buttonStyle(.plain)
                    ListDivider(inset: bill.id == bills.last?.id ? 16 : 64)
                }
                Button {
                    tab = .accounts
                } label: {
                    HStack(spacing: 10) {
                        Text("Building toward next bills")
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 8)
                        Text(Yen.format(building))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                        Chevron()
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .frame(minHeight: Metrics.compactRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
    }

    /// Not on the canvas: the partner balance and entries waiting for a look, shown only when there's
    /// something to do so these features stay one tap away.
    @ViewBuilder
    private func toDoSection(_ ledger: Ledger) -> some View {
        let owed = ledger.partnerOwed
        let review = entries.filter { ($0.kind == .payoff && !$0.isConfirmed) || $0.needsReview }.count
        if owed != 0 || review > 0 {
            SectionTitle("To do")
                .padding(.top, Metrics.sectionSpacing)
            CardList {
                if owed != 0 {
                    NavigationLink {
                        PartnerView()
                    } label: {
                        KRow(owed > 0 ? "\(partnerName) owes you" : "\(partnerName) paid back extra",
                             subtitle: "Settle up or mark items repaid", chevron: true) {
                            SymbolTile(symbol: "person.2.fill", hue: .pink)
                        } trailing: {
                            Text(Yen.format(abs(owed)))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if owed != 0 && review > 0 { ListDivider() }
                if review > 0 {
                    NavigationLink {
                        ReviewListView()
                    } label: {
                        KRow("To review", subtitle: "Card payoffs to confirm, entries from Shortcuts", chevron: true) {
                            SymbolTile(symbol: "checklist", hue: .orange)
                        } trailing: {
                            Text("\(review)")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func recentSection(now: Date) -> some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        let recent = Array(entries.filter { $0.date <= now }.prefix(4))
        SectionTitle("Recent") {
            Button("See All") { tab = .activity }
        }
        .padding(.top, Metrics.sectionSpacing)
        if recent.isEmpty {
            Text("Nothing logged yet. Tap + to add your first expense.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .kCard()
                .padding(.top, 10)
        } else {
            CardList {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { ListDivider() }
                    Button {
                        editing = entry
                    } label: {
                        TransactionRow(entry: entry, lookup: lookup, partnerName: partnerName, timeStyle: .relative, now: now)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: Actions

    private func startTransfer(for reminder: BillReminder, ledger: Ledger, now: Date) {
        guard let payer = reminder.payFrom else { return }
        let source = Billing.suggestedSource(for: payer, amount: reminder.shortfall, ledger: ledger, now: now)
        let date = reminder.dueDate.formatted(.dateTime.month(.abbreviated).day())
        draft = EntryDraft(kind: .transfer, amount: reminder.shortfall, accountID: source?.id, toAccountID: payer.id,
                           note: "For \(reminder.account.name) bill",
                           reason: "Covers the \(reminder.account.name) bill on \(date)")
    }
}

// MARK: - Cards and rows

/// "Store Card bill not covered": shown as soon as a statement closes that the paying account can't
/// cover on the due date, with a one-tap transfer.
struct ShortfallCard: View {
    let reminder: BillReminder
    let onTransfer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                SymbolTile(symbol: "exclamationmark.triangle", hue: .orange, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(reminder.account.name) bill not covered")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    message
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button("Transfer \(Yen.format(reminder.shortfall))", action: onTransfer)
                    .buttonStyle(.pill)
                    .disabled(reminder.payFrom == nil)
                NavigationLink("View bill") {
                    AccountDetailView(account: reminder.account)
                }
                .buttonStyle(.pillSecondary)
            }
        }
        .kCard()
    }

    private var message: Text {
        let payer = reminder.payFrom?.name ?? "The paying account"
        let short = Text("\(Yen.format(reminder.shortfall)) short")
            .fontWeight(.semibold)
            .foregroundStyle(Palette.warning)
        let date = reminder.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return Text("\(payer) is \(short) for the \(Yen.format(reminder.due)) payment on \(date).")
    }
}

/// This month's budget: what's left, the daily allowance, a bar with today's pace and a like-for-like
/// comparison with the same days of last month.
struct BudgetHeroCard: View {
    let pace: BudgetPace
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            content
        }
        .buttonStyle(.plain)
    }

    private var monthName: String { pace.interval.start.formatted(.dateTime.month(.wide)) }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(monthName) budget")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                HStack(spacing: 5) {
                    Text("Day \(pace.daysElapsed) of \(pace.daysInMonth)")
                    Chevron()
                }
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
            }
            if pace.budget > 0 {
                budgeted
            } else {
                unbudgeted
            }
        }
        .kCard(padding: 18)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var budgeted: some View {
        let over = pace.left < 0
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Yen.format(abs(pace.left)))
                .font(.kHero)
                .tracking(-1.2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(over ? Palette.negativeText : Palette.textPrimary)
            Text(over ? "over" : "left")
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.top, 10)
        Text(allowance)
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .monospacedDigit()
            .padding(.top, 2)
        PaceBar(fraction: pace.fraction, pace: pace.isCurrentMonth ? pace.paceFraction : nil)
            .padding(.top, 16)
        HStack {
            Text("Spent \(Text(Yen.format(pace.spent)).fontWeight(.semibold).foregroundStyle(Palette.textPrimary))")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
            Spacer(minLength: 8)
            PaceStatusChip(status: pace.status)
        }
        .padding(.top, 8)
        if pace.previousSameDays > 0 {
            ComparisonLine(delta: pace.vsPrevious, label: pace.comparisonLabel())
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var unbudgeted: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Yen.format(pace.spent))
                .font(.kHero)
                .tracking(-1.2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Palette.textPrimary)
            Text("spent")
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.top, 10)
        Text("Give categories a monthly budget to see what's left and today's pace.")
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, 2)
        if pace.previousSameDays > 0 {
            ComparisonLine(delta: pace.vsPrevious, label: pace.comparisonLabel())
                .padding(.top, 8)
        }
    }

    private var allowance: String {
        let base = "of \(Yen.format(pace.budget))"
        guard pace.isCurrentMonth, pace.perDay > 0 else { return base }
        if pace.daysRemaining == 0 { return "\(base) · last day" }
        let days = pace.daysRemaining == 1 ? "1 day" : "\(pace.daysRemaining) days"
        return "\(base) · \(Yen.format(pace.perDay)) a day for \(days)"
    }
}

/// Budget bar with "Today" under the pace tick.
struct PaceBar: View {
    let fraction: Double
    let pace: Double?
    var tint: Color = Palette.accentData
    var height: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            BudgetBar(fraction: fraction, pace: pace, tint: tint, height: height)
            if let pace {
                GeometryReader { geo in
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize()
                        .position(x: min(max(geo.size.width * pace, 16), max(geo.size.width - 16, 16)), y: 10)
                }
                .frame(height: 16)
            }
        }
        .accessibilityHidden(true)
    }
}

struct PaceStatusChip: View {
    let status: PaceStatus

    var body: some View {
        switch status {
        case .over: StatusChip(text: "Over budget", tint: Palette.negativeText, dot: true)
        case .atRisk: StatusChip(text: "Ahead of pace", tint: Palette.warning, dot: true)
        case .onTrack: StatusChip(text: "On track", tint: Palette.positive, dot: true)
        }
    }
}

/// "¥6,200 less than Oct 1–18" in green, or "more" in orange.
struct ComparisonLine: View {
    let delta: Int
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            if delta != 0 {
                Image(systemName: delta < 0 ? "arrow.down.right" : "arrow.up.right")
                    .font(.footnote.weight(.bold))
            }
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(delta < 0 ? Palette.positive : (delta > 0 ? Palette.warning : Palette.textSecondary))
    }

    private var text: String {
        if delta < 0 { return "\(Yen.format(-delta)) less than \(label)" }
        if delta > 0 { return "\(Yen.format(delta)) more than \(label)" }
        return "Same as \(label)"
    }
}

/// A category over budget or likely to run out.
struct AttentionRow: View {
    let item: CategoryPace
    let monthStart: Date

    var body: some View {
        KRow(item.category.name, subtitle: subtitle, chevron: true) {
            CategoryIcon(category: item.category)
        } trailing: {
            Text(trailing)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.status == .over ? Palette.negativeText : Palette.warning)
        }
    }

    private var subtitle: String {
        if item.status == .over {
            return "\(Yen.format(item.spent)) of \(Yen.format(item.budget))"
        }
        if let day = item.runsOutDay,
           let date = Calendar.kakeibo.date(byAdding: .day, value: day - 1, to: monthStart) {
            return "Runs out around \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "Ahead of today's pace"
    }

    private var trailing: String {
        item.status == .over ? "\(Yen.format(item.spent - item.budget)) over" : "\(Yen.format(item.left)) left"
    }
}

/// An unpaid statement: due date, paying account and whether it's covered.
struct BillRow: View {
    let reminder: BillReminder
    var warns = true

    var body: some View {
        KRow(reminder.account.name, subtitle: subtitle) {
            AccountIcon(account: reminder.account)
        } trailing: {
            AmountStack(Yen.format(reminder.due)) {
                status
            }
        }
    }

    private var subtitle: String {
        let date = reminder.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if let payer = reminder.payFrom { return "\(date) · \(payer.name)" }
        return date
    }

    @ViewBuilder
    private var status: some View {
        if reminder.isOverdue {
            Text("Overdue")
                .fontWeight(.semibold)
                .foregroundStyle(Palette.negativeText)
        } else if reminder.payFrom == nil {
            Text("Pay it yourself")
        } else if warns && reminder.shortfall > 0 {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                Text("\(Yen.format(reminder.shortfall)) short")
            }
            .fontWeight(.semibold)
            .foregroundStyle(Palette.warning)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "checkmark").font(.caption2.weight(.bold))
                Text("Covered")
            }
            .foregroundStyle(Palette.positive)
        }
    }
}
