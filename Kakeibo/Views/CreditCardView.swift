import SwiftData
import SwiftUI

/// A credit card (CreditCard artboard): the card, a warning when the paying account will be short, the
/// closed statement, the bill building now, and past statements with how they were paid.
struct CreditCardView: View {
    let card: Account

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.shortfallWarnings) private var shortfallWarnings = true
    @State private var editing = false
    @State private var draft: EntryDraft?

    var body: some View {
        let now = Date()
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let status = Billing.status(for: card, ledger: ledger, now: now)
        let reminder = Billing.reminders(ledger: ledger, now: now).first { $0.account.id == card.id }
        let color = AccountLook.cardColor(card)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CardFace(name: card.name, color: color, available: card.available(ledger: ledger),
                         rule: BillingText.rule(card))
                if shortfallWarnings, let reminder, reminder.shortfall > 0 {
                    PaymentWarning(reminder: reminder, now: now, onTransfer: {
                        draft = EntryDraft.shortfallTransfer(for: reminder, ledger: ledger, now: now)
                    }, onChangeAccount: {
                        editing = true
                    })
                    .padding(.top, 16)
                }
                SectionCaps(title: "Current bill")
                    .padding(.top, Metrics.sectionSpacing)
                currentBill(status, ledger: ledger, now: now)
                    .padding(.top, 8)
                SectionCaps(title: "Next bill · building")
                    .padding(.top, Metrics.sectionSpacing)
                nextBill(status, ledger: ledger, color: color, now: now)
                    .padding(.top, 8)
                pastStatements(ledger: ledger, now: now)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .kScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            CardSetupView(card: card)
        }
        .sheet(item: $draft) { draft in
            EntryEditorView(mode: .new, draft: draft)
        }
    }

    // MARK: Sections

    private func currentBill(_ status: CardStatus, ledger: Ledger, now: Date) -> some View {
        let cycle = status.cycle
        let total = -ledger.balance(of: card, before: cycle.closingBoundary)
        let payer = ledger.account(card.payFromAccountID)
        let count = CardHistory.entries(of: card, in: cycle, ledger: ledger).count
        return CardList {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(BillingText.period(cycle)) statement")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Text(Yen.format(status.due > 0 ? status.due : max(total, 0)))
                    .font(.kStat)
                    .tracking(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text(dueLine(status, total: total, now: now))
                    .font(.subheadline)
                    .foregroundStyle(status.isOverdue ? Palette.negativeText : Palette.textSecondary)
                if status.due > 0, let reason = BillingText.shiftReason(cycle) {
                    Text("Moved because \(reason).")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            ListDivider(inset: 16)
            if let payer {
                NavigationLink {
                    AccountDetailView(account: payer)
                } label: {
                    InfoRow(title: "Pays from", chevron: true) {
                        HStack(spacing: 8) {
                            AccountIcon(account: payer, size: 22)
                            Text(payer.name)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    editing = true
                } label: {
                    InfoRow(title: "Pays from", chevron: true) { Text("Not set") }
                }
                .buttonStyle(.plain)
            }
            ListDivider(inset: 16)
            NavigationLink {
                CycleEntriesView(card: card, cycle: cycle)
            } label: {
                InfoRow(title: "Statement entries", chevron: true) { Text("\(count)") }
            }
            .buttonStyle(.plain)
            if status.due > 0 && payer != nil {
                ListDivider(inset: 16)
                Button {
                    recordPayoff(amount: status.due, cycle: cycle)
                } label: {
                    HStack {
                        Text("Record payment of \(Yen.format(status.due)) now")
                            .foregroundStyle(Palette.accentTint)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: Metrics.compactRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dueLine(_ status: CardStatus, total: Int, now: Date) -> String {
        let date = BillingText.day(status.dueDate)
        if status.isOverdue { return "Was due \(date)" }
        if status.due == 0 { return total > 0 ? "Paid" : "Nothing to pay" }
        let days = Calendar.kakeibo.dateComponents([.day], from: Calendar.kakeibo.startOfDay(for: now), to: status.dueDate).day ?? 0
        switch days {
        case 0: return "Due today"
        case 1: return "Due \(date) · tomorrow"
        default: return "Due \(date) · in \(days) days"
        }
    }

    private func nextBill(_ status: CardStatus, ledger: Ledger, color: CardColor, now: Date) -> some View {
        let cycle = status.next
        let calendar = Calendar.kakeibo
        let length = max(calendar.dateComponents([.day], from: cycle.start, to: cycle.closingBoundary).day ?? 30, 1)
        let elapsed = min(max((calendar.dateComponents([.day], from: cycle.start, to: now).day ?? 0) + 1, 0), length)
        let toClose = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: cycle.closingDate).day ?? 0, 0)
        let count = CardHistory.entries(of: card, in: cycle, ledger: ledger).count
        return CardList {
            VStack(alignment: .leading, spacing: 0) {
                Text(BillingText.period(cycle))
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Yen.format(status.nextSoFar))
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text("so far")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                BudgetBar(fraction: Double(elapsed) / Double(length), tint: color.bright)
                    .padding(.top, 12)
                    .accessibilityLabel("Day \(elapsed) of \(length) in this billing cycle")
                HStack {
                    Text(cycle.start.formatted(.dateTime.month(.abbreviated).day()))
                    Spacer()
                    Text("Closes \(BillingText.day(cycle.closingDate)) · \(toClose == 0 ? "today" : "in \(toClose) days")")
                }
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 6)
                Text("Due \(BillingText.day(cycle.paymentDate))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, 12)
                if let sentence = shiftSentence(cycle) {
                    Text(sentence)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            ListDivider(inset: 16)
            NavigationLink {
                CycleEntriesView(card: card, cycle: cycle)
            } label: {
                InfoRow(title: count == 1 ? "1 entry this cycle" : "\(count) entries this cycle", chevron: true) { EmptyView() }
            }
            .buttonStyle(.plain)
        }
    }

    /// "Jan 2 falls on a Saturday, so payment moves to the next business day."
    private func shiftSentence(_ cycle: BillCycle) -> String? {
        let nominal = cycle.nominalPaymentDate.formatted(.dateTime.month(.abbreviated).day())
        let direction = card.holidayShift == .previousBusinessDay ? "previous" : "next"
        switch Billing.shiftCause(of: cycle) {
        case .weekend(let weekday): return "\(nominal) falls on a \(weekday), so payment moves to the \(direction) business day."
        case .holiday(let name):
            let what = name == "Bank holiday" ? "a bank holiday" : name
            return "\(nominal) is \(what), so payment moves to the \(direction) business day."
        case nil: return nil
        }
    }

    @ViewBuilder
    private func pastStatements(ledger: Ledger, now: Date) -> some View {
        let statements = CardHistory.pastStatements(for: card, ledger: ledger, now: now)
        if !statements.isEmpty {
            SectionCaps(title: "Past statements")
                .padding(.top, Metrics.sectionSpacing)
            CardList {
                ForEach(Array(statements.enumerated()), id: \.element.id) { index, statement in
                    if index > 0 { ListDivider(inset: 16) }
                    PastStatementRow(statement: statement, payer: ledger.account(statement.payment?.accountID))
                }
            }
            .padding(.top, 8)
        }
    }

    private func recordPayoff(amount: Int, cycle: BillCycle) {
        guard let from = card.payFromAccountID else { return }
        let payoff = Entry(kind: .payoff, amount: amount, date: Date(), accountID: from, toAccountID: card.id)
        payoff.billCycleKey = cycle.key(for: card.id)
        payoff.isConfirmed = true
        context.insert(payoff)
        context.saveAndRefresh()
        Haptics.success()
    }
}

// MARK: - Pieces

/// A credit card drawn as a card: name, what's available, the chip and its billing days.
struct CardFace: View {
    let name: String
    let color: CardColor
    var available: Int?
    var rule: String
    var height: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(name.isEmpty ? "New Card" : name)
                    .font(.title3.bold())
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let available {
                    Text("\(Yen.format(available)) available")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .opacity(0.88)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 30, height: 22)
                Spacer()
                Text(rule)
                    .font(.footnote.weight(.medium))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(color.color)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 200, height: 200)
                .offset(x: 40, y: -60)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

/// "Online Bank is ¥11,300 short": what's due, what the account will have, a one-tap transfer and when
/// the reminders go out.
struct PaymentWarning: View {
    let reminder: BillReminder
    let now: Date
    let onTransfer: () -> Void
    let onChangeAccount: () -> Void

    var body: some View {
        let payer = reminder.payFrom?.name ?? "The paying account"
        let has = max(reminder.due - reminder.shortfall, 0)
        let payerHue = reminder.payFrom.map { AccountLook.of($0).hue } ?? .teal
        let reminders = reminder.account.paymentReminder ? Billing.reminderDates(dueDate: reminder.dueDate, now: now) : []
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                SymbolTile(symbol: "exclamationmark.triangle", hue: .orange, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(payer) is \(Yen.format(reminder.shortfall)) short")
                        .font(.headline)
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(Yen.format(reminder.due)) is due \(BillingText.day(reminder.dueDate)), and \(payer) will have \(Yen.format(has)).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.warning.opacity(0.35))
                    Capsule()
                        .fill(payerHue.color)
                        .frame(width: geo.size.width * min(Double(has) / Double(max(reminder.due, 1)), 1))
                }
            }
            .frame(height: 10)
            .padding(.top, 14)
            .accessibilityLabel("\(payer) covers \(Int((Double(has) / Double(max(reminder.due, 1)) * 100).rounded()))% of the bill")
            HStack {
                Text("\(payer) \(Yen.format(has))").foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("Short \(Yen.format(reminder.shortfall))")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.warning)
            }
            .font(.footnote)
            .monospacedDigit()
            .padding(.top, 6)
            HStack(spacing: 10) {
                Button("Transfer \(Yen.format(reminder.shortfall))", action: onTransfer)
                    .buttonStyle(.pill)
                Button("Change account", action: onChangeAccount)
                    .buttonStyle(.pillSecondary)
            }
            .padding(.top, 14)
            if !reminders.isEmpty {
                Text("We'll remind you again on \(reminders.map { BillingText.day($0) }.joined(separator: " and ")).")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 12)
            }
        }
        .kCard()
    }
}

struct PastStatementRow: View {
    let statement: PastStatement
    let payer: Account?

    var body: some View {
        KRow(BillingText.period(statement.cycle), minHeight: 64) {
            EmptyView()
        } subtitle: {
            HStack(spacing: 6) {
                Text(detail)
                if statement.payment?.isAutoCreated == true { AutoBadge() }
            }
        } trailing: {
            AmountStack(Yen.format(statement.amount)) {
                if statement.isPaid {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark").font(.caption2.weight(.bold))
                        Text("Paid")
                    }
                    .foregroundStyle(Palette.positive)
                } else {
                    Text("\(Yen.format(statement.due)) unpaid")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.warning)
                }
            }
        }
    }

    private var detail: String {
        guard let payment = statement.payment else {
            return statement.isPaid ? "Settled" : "Due \(BillingText.day(statement.cycle.paymentDate))"
        }
        let day = BillingText.day(payment.date)
        return payer.map { "Paid \(day) · \($0.name)" } ?? "Paid \(day)"
    }
}

/// Purchases on one statement.
struct CycleEntriesView: View {
    let card: Account
    let cycle: BillCycle
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName

    var body: some View {
        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        let lookup = Lookup(accounts: accounts, categories: categories)
        let items = CardHistory.entries(of: card, in: cycle, ledger: ledger)
        List {
            if items.isEmpty {
                Text("Nothing charged yet.")
                    .foregroundStyle(Palette.textSecondary)
                    .listRowBackground(Palette.card)
            }
            ForEach(items) { entry in
                TransactionRow(entry: entry, lookup: lookup, partnerName: partnerName, timeStyle: .relative)
                    .background {
                        NavigationLink {
                            TransactionDetailView(entry: entry)
                        } label: {
                            EmptyView()
                        }
                        .opacity(0)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Palette.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .kScreenBackground()
        .navigationTitle(BillingText.period(cycle))
        .navigationBarTitleDisplayMode(.inline)
    }
}
