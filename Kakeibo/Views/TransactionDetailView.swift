import SwiftData
import SwiftUI

/// One entry (Transaction artboard): what, when and where from, how it lands on a card bill, what it
/// did to its category's budget, and Log Again.
struct TransactionDetailView: View {
    let entry: Entry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var draft: EntryDraft?
    @State private var gone = false
    @State private var confirmPayoff = false

    /// True once the entry has been deleted, here or from the editor; its fields can't be read then.
    private var isGone: Bool { gone || entry.isDeleted || entry.modelContext == nil }

    var body: some View {
        Group {
            if isGone {
                Color.clear
            } else {
                content
            }
        }
        .kScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
                    .disabled(isGone)
            }
        }
        .sheet(isPresented: $editing, onDismiss: {
            if isGone { dismiss() }
        }) {
            EntryEditorRouter(entry: entry)
        }
        .sheet(item: $draft) { draft in
            EntryEditorView(mode: .new, draft: draft)
        }
        .confirmationDialog("Pay off the rest on the next bill?", isPresented: $confirmPayoff, titleVisibility: .visible) {
            Button("Pay Off the Rest") { payOff() }
        } message: {
            Text("Every installment not yet billed moves onto the bill that's open now. Fees stop at what's already been charged.")
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteEntry)
        }
    }

    private var content: some View {
        let lookup = Lookup(accounts: accounts, categories: categories)
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let look = EntryPresentation(entry: entry, lookup: lookup, partnerName: partnerName)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(look)
                infoCard(look)
                    .padding(.top, 24)
                if let plan = ledger.plan(for: entry) {
                    SectionCaps(title: "Installments")
                        .padding(.top, Metrics.sectionSpacing)
                    InstallmentPlanCard(plan: plan, now: Date()) { confirmPayoff = true }
                        .padding(.top, 8)
                    SectionCaps(title: "Card bills")
                        .padding(.top, Metrics.sectionSpacing)
                    InstallmentTimeline(plan: plan)
                        .padding(.top, 8)
                } else if entry.kind == .expense, let card = look.account, card.kind == .credit {
                    SectionCaps(title: "Card bill")
                        .padding(.top, Metrics.sectionSpacing)
                    CardBillTimeline(purchaseDate: entry.date, card: card, ledger: ledger)
                        .padding(.top, 8)
                }
                if entry.kind == .expense, let category = look.category, category.monthlyBudget > 0, !category.isArchived {
                    SectionCaps(title: "Budget")
                        .padding(.top, Metrics.sectionSpacing)
                    budgetCard(category, ledger: ledger)
                        .padding(.top, 8)
                }
                actions
                    .padding(.top, 24)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
        }
    }

    // MARK: Pieces

    private func header(_ look: EntryPresentation) -> some View {
        VStack(spacing: 0) {
            look.icon(size: 64)
            Text(look.amountText)
                .font(.kHero)
                .tracking(-1.2)
                .monospacedDigit()
                .foregroundStyle([.transfer, .payoff, .adjust].contains(entry.kind) ? Palette.textPrimary : look.amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 12)
            Text(look.title)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2)
            Text("\(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func infoCard(_ look: EntryPresentation) -> some View {
        let dateText = "\(entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())), \(entry.date.formatted(date: .omitted, time: .shortened))"
        CardList {
            switch entry.kind {
            case .expense, .income:
                InfoRow(title: "Category") {
                    HStack(spacing: 8) {
                        CategoryIcon(category: look.category, size: 22)
                        Text(look.category?.name ?? "Uncategorised")
                    }
                }
                ListDivider(inset: 16)
                accountRow(entry.kind == .income ? "Received in" : "Paid with", account: look.account)
            case .transfer, .payoff:
                accountRow("From", account: look.account)
                ListDivider(inset: 16)
                accountRow(entry.kind == .payoff ? "Card" : "To", account: look.toAccount)
            case .settlement:
                accountRow("Received in", account: look.account)
            case .adjust:
                accountRow("Account", account: look.account)
            }
            ListDivider(inset: 16)
            InfoRow(title: "Date") { Text(dateText) }
            if !entry.merchant.isEmpty && !entry.note.isEmpty {
                ListDivider(inset: 16)
                InfoRow(title: "Shop") { Text(entry.merchant) }
            }
            if !entry.note.isEmpty {
                ListDivider(inset: 16)
                InfoRow(title: "Note") { Text(entry.note) }
            }
            if entry.isSharedExpense {
                ListDivider(inset: 16)
                InfoRow(title: "Split with \(partnerName)") {
                    Text("Your share \(Yen.format(entry.myShare))").monospacedDigit()
                }
            }
            if entry.kind == .expense && entry.isRefund {
                ListDivider(inset: 16)
                InfoRow(title: "Refund") { Text("Reduces spending") }
            }
            if entry.kind == .payoff {
                ListDivider(inset: 16)
                InfoRow(title: entry.isAutoCreated ? "Recorded automatically" : "Card payment") {
                    Text(entry.isConfirmed ? "Confirmed" : "To confirm")
                        .foregroundStyle(entry.isConfirmed ? Palette.textSecondary : Palette.warning)
                }
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ title: String, account: Account?) -> some View {
        if let account {
            NavigationLink {
                AccountDetailView(account: account)
            } label: {
                InfoRow(title: title, chevron: true) {
                    HStack(spacing: 8) {
                        AccountIcon(account: account, size: 22)
                        Text(account.name)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            InfoRow(title: title) { Text("No account") }
        }
    }

    private func budgetCard(_ category: BudgetCategory, ledger: Ledger) -> some View {
        // An installment plan shows this month, when its slices count; anything else shows the purchase month.
        let pace = BudgetPace(ledger: ledger, month: ledger.plan(for: entry) == nil ? entry.date : Date())
        let item = (pace.needsAttention + pace.onTrack).first { $0.category.id == category.id }
        let spent = item?.spent ?? 0
        let monthName = pace.interval.start.formatted(.dateTime.month(.wide))
        let over = spent > category.monthlyBudget
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(category.name) in \(monthName)")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Text(over ? "\(Yen.format(spent - category.monthlyBudget)) over" : "\(Yen.format(category.monthlyBudget - spent)) left")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(over ? Palette.negativeText : (item?.status == .atRisk ? Palette.warning : Palette.textSecondary))
            }
            BudgetBar(fraction: item?.fraction ?? 0, pace: pace.isCurrentMonth ? item?.paceFraction : nil,
                      tint: CategoryLook.of(category).tint, height: 8)
            Text("This entry made up \(Yen.format(countedThisMonth(ledger: ledger, interval: pace.interval))) of \(Yen.format(spent)) spent")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
    }

    private var actions: some View {
        CardList {
            if entry.kind == .expense || entry.kind == .income || entry.kind == .transfer {
                Button {
                    logAgain()
                } label: {
                    actionLabel("Log Again", symbol: "plus.square.on.square", color: Palette.accentTint)
                }
                .buttonStyle(.plain)
                ListDivider(inset: 46)
            }
            Button {
                confirmDelete = true
            } label: {
                actionLabel("Delete Transaction", symbol: "trash", color: Palette.negativeText)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20)
            Text(title)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .frame(minHeight: Metrics.compactRowHeight)
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func logAgain() {
        draft = EntryDraft(kind: entry.kind, amount: entry.amount, accountID: entry.accountID,
                           toAccountID: entry.kind == .transfer ? entry.toAccountID : nil,
                           categoryID: entry.categoryID, note: entry.note, merchant: entry.merchant)
    }

    /// What this entry counts toward its category in the month shown: the whole amount, or for an
    /// installment plan the slices paid that month.
    private func countedThisMonth(ledger: Ledger, interval: DateInterval) -> Int {
        guard let plan = ledger.plan(for: entry), plan.mode != .all else {
            return entry.isRefund ? -entry.amount : entry.myShare
        }
        guard plan.mode == .monthly else { return 0 }
        return plan.slices.filter { $0.paymentDate >= interval.start && $0.paymentDate < interval.end }.reduce(0) { $0 + $1.myShare }
    }

    private func payOff() {
        entry.installmentPaidOffAt = Date()
        context.saveAndRefresh()
        Haptics.success()
    }

    private func deleteEntry() {
        gone = true
        context.delete(entry)
        context.saveAndRefresh()
        Haptics.warning()
        dismiss()
    }
}

/// A label on the left and its value on the right, 50 pt high, as in the canvas's detail cards.
struct InfoRow<Value: View>: View {
    let title: String
    var chevron = false
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            value
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            if chevron { Chevron() }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: Metrics.compactRowHeight)
        .contentShape(Rectangle())
    }
}

/// How a card purchase becomes a payment: charged, statement closes, paid from the bank (moved off
/// weekends and bank holidays, with the reason).
struct CardBillTimeline: View {
    let purchaseDate: Date
    let card: Account
    let ledger: Ledger
    var now = Date()

    var body: some View {
        let cycle = Billing.cycle(containing: purchaseDate, rule: card.billingRule)
        let closed = cycle.closingBoundary <= now
        let total = closed
            ? Billing.statementTotal(for: card, cycle: cycle, ledger: ledger)
            : Billing.status(for: card, ledger: ledger, now: now).nextSoFar
        let period = BillingText.period(cycle)
        VStack(alignment: .leading, spacing: 0) {
            TimelineStep(title: BillingText.day(purchaseDate), detail: "Charged to \(card.name)", done: true, last: false)
            TimelineStep(title: BillingText.day(cycle.closingDate),
                         detail: closed ? "Statement closed · \(period) \(Yen.format(total))"
                                        : "Statement closes · \(period) so far \(Yen.format(total))",
                         done: closed, last: false)
            TimelineStep(title: BillingText.day(cycle.paymentDate), detail: paymentLine(cycle), done: cycle.paymentDate <= now, last: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
    }

    private func paymentLine(_ cycle: BillCycle) -> String {
        let payer = ledger.account(card.payFromAccountID)
        var line = payer.map { (cycle.paymentDate <= now ? "Paid from " : "Pays from ") + $0.name } ?? "You pay it yourself"
        if let reason = BillingText.shiftReason(cycle) { line += " · \(reason)" }
        return line
    }
}

/// One stop on a timeline: a filled dot for what's happened, a ring for what's coming.
struct TimelineStep: View {
    let title: String
    let detail: String
    let done: Bool
    let last: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if done {
                    Circle().fill(Palette.accentData)
                } else {
                    Circle().strokeBorder(Palette.textSecondary, lineWidth: 2)
                }
            }
            .frame(width: 12, height: 12)
            .padding(.top, 4)
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, last ? 0 : 10)
            Spacer(minLength: 0)
        }
        .frame(minHeight: last ? 0 : 48, alignment: .top)
        .background(alignment: .topLeading) {
            if !last {
                GeometryReader { geo in
                    Rectangle()
                        .fill(done ? Palette.accentData.opacity(0.55) : Palette.textSecondary.opacity(0.4))
                        .frame(width: 2, height: max(geo.size.height - 20, 0))
                        .offset(x: 6, y: 20)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Wording for billing dates, shared by the card screens and the transaction timeline.
enum BillingText {
    /// "Tue, Nov 17".
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Nov 1–30" within a month, "Oct 11 – Nov 10" across two.
    static func period(_ cycle: BillCycle, calendar: Calendar = .kakeibo) -> String {
        let start = cycle.start
        let end = cycle.closingDate
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(start.formatted(.dateTime.month(.abbreviated).day()))–\(calendar.component(.day, from: end))"
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// "the 27th is a Sunday", "the 3rd is Culture Day", nil if the payment didn't move.
    static func shiftReason(_ cycle: BillCycle, calendar: Calendar = .kakeibo) -> String? {
        let nominal = "the \(Ordinal.day(calendar.component(.day, from: cycle.nominalPaymentDate), endOfMonth: "last day"))"
        switch Billing.shiftCause(of: cycle, calendar: calendar) {
        case .weekend(let weekday): return "\(nominal) is a \(weekday)"
        case .holiday(let name): return "\(nominal) is \(name == "Bank holiday" ? "a bank holiday" : name)"
        case nil: return nil
        }
    }

    /// "Closes 10th · Pays 2nd", "Closes end of month · Pays 27th".
    static func rule(_ account: Account) -> String {
        "Closes \(Ordinal.day(account.closingDay)) · Pays \(Ordinal.day(account.paymentDay))"
    }
}
