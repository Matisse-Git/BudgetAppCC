import SwiftData
import SwiftUI

/// Adding or editing a credit card (CardSetup artboard): name and colour, the billing rules with a
/// worked example, the paying account, where the card stands today, and its alerts.
struct CardSetupView: View {
    let card: Account?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var entries: [Entry]

    @State private var name = ""
    @State private var color: CardColor = .blue
    @State private var closingDay = 31
    @State private var paymentDay = 27
    @State private var paymentOffset = 1
    @State private var shift: HolidayShift = .nextBusinessDay
    @State private var payFrom: UUID?
    @State private var limit = 0
    @State private var autoPayoff = true
    @State private var reminder = true
    @State private var warn = true
    @State private var unpaid = 0
    @State private var spentSince = 0
    @State private var archived = false
    @State private var showsPaymentWheel = false
    @State private var loaded = false

    /// A new card, or one nothing has been logged on yet (like the seeded cards during first run):
    /// where it stands today can still be set.
    private var setsOpeningAmounts: Bool {
        guard let card else { return true }
        return !entries.contains { $0.accountID == card.id || $0.toAccountID == card.id }
    }

    private var rule: BillingRule {
        BillingRule(closingDay: closingDay, paymentDay: paymentDay, paymentMonthOffset: paymentOffset, shift: shift)
    }

    private var moneyAccounts: [Account] {
        accounts.filter { ($0.holdsMoney && !$0.isArchived) || $0.id == payFrom }
    }

    private var payerName: String {
        accounts.first { $0.id == payFrom }?.name ?? "the paying account"
    }

    var body: some View {
        let now = Date()
        let closed = Billing.latestCycle(rule: rule, now: now)
        let open = Billing.shifted(closed, by: 1, rule: rule)
        NavigationStack {
            Form {
                Section {
                    CardFace(name: name, color: color, available: limit > 0 ? limit - unpaid - spentSince : nil,
                             rule: "Closes \(Ordinal.day(closingDay)) · Pays \(Ordinal.day(paymentDay))", height: 116)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    LabeledContent("Name") {
                        TextField("Card name", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Color") {
                        HStack(spacing: 9) {
                            ForEach(CardColor.allCases) { option in
                                Button {
                                    color = option
                                    Haptics.selection()
                                } label: {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 24, height: 24)
                                        .padding(2)
                                        .overlay(Circle().strokeBorder(color == option ? Palette.textPrimary : Color.clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.name)
                                .accessibilityAddTraits(color == option ? [.isSelected] : [])
                            }
                        }
                    }
                }
                .listRowBackground(Palette.sheetRow)

                Section {
                    Picker("Closing day", selection: $closingDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(day == 31 ? "End of month" : Ordinal.day(day)).tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    Button {
                        withAnimation(.snappy) { showsPaymentWheel.toggle() }
                    } label: {
                        LabeledContent("Payment day") {
                            Text("\(Ordinal.day(paymentDay, endOfMonth: "End of month")), \(offsetLabel(paymentOffset).lowercased())")
                                .foregroundStyle(Palette.accentTint)
                        }
                        .foregroundStyle(Palette.textPrimary)
                    }
                    if showsPaymentWheel {
                        HStack(spacing: 0) {
                            Picker("Day", selection: $paymentDay) {
                                ForEach(1...31, id: \.self) { day in
                                    Text(day == 31 ? "End of month" : Ordinal.day(day)).tag(day)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .clipped()
                            Picker("Month", selection: $paymentOffset) {
                                ForEach(0...2, id: \.self) { offset in
                                    Text(offsetLabel(offset)).tag(offset)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .clipped()
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 170)
                    }
                    Picker("Weekend or holiday", selection: $shift) {
                        ForEach(HolidayShift.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Billing")
                } footer: {
                    example(open)
                }
                .listRowBackground(Palette.sheetRow)

                Section("Payment") {
                    Picker("Pays from", selection: $payFrom) {
                        Text("Not set (I pay it myself)").tag(UUID?.none)
                        ForEach(moneyAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    Toggle("Record each payment automatically", isOn: $autoPayoff)
                        .disabled(payFrom == nil)
                    LabeledContent("Credit limit") {
                        TextField("Optional", value: $limit, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
                .listRowBackground(Palette.sheetRow)

                if setsOpeningAmounts {
                    Section {
                        LabeledContent("Unpaid statement") {
                            TextField("¥0", value: $unpaid, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                        LabeledContent("Due", value: BillingText.day(closed.paymentDate))
                        LabeledContent("Spent since \(open.start.formatted(.dateTime.month(.abbreviated).day()))") {
                            TextField("¥0", value: $spentSince, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                    } header: {
                        Text("Where it stands today")
                    } footer: {
                        Text("Copy these from your latest statement so the first bill is right, or log past purchases one by one instead.")
                    }
                    .listRowBackground(Palette.sheetRow)
                }

                Section("Alerts") {
                    Toggle(isOn: $reminder) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Payment reminder")
                            Text("3 days and 1 day before each payment")
                                .font(.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Toggle(isOn: $warn) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Warn if \(payerName) is short")
                            Text("Checked when each bill closes")
                                .font(.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .listRowBackground(Palette.sheetRow)

                if card != nil {
                    Section {
                        Toggle("Archived", isOn: $archived)
                    } footer: {
                        Text("Archived cards are hidden from pickers but keep their history.")
                    }
                    .listRowBackground(Palette.sheetRow)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.sheet)
            .navigationTitle(card == nil ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(card == nil ? "Add card" : "Save")
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sensoryFeedback(.selection, trigger: shift)
            .sensoryFeedback(.selection, trigger: closingDay)
            .onAppear(perform: load)
        }
        .presentationBackground(Palette.sheet)
    }

    private func offsetLabel(_ offset: Int) -> String {
        switch offset {
        case 0: return "Same month"
        case 2: return "Month after next"
        default: return "Next month"
        }
    }

    /// "Spending from Nov 1–30 closes on Mon, Nov 30 and is paid on Mon, Dec 28, because the 27th is a Sunday."
    private func example(_ cycle: BillCycle) -> Text {
        let paid = Text(BillingText.day(cycle.paymentDate)).fontWeight(.semibold).foregroundStyle(Palette.textPrimary)
        let because = BillingText.shiftReason(cycle).map { ", because \($0)" } ?? ""
        return Text("Spending from \(BillingText.period(cycle)) closes on \(BillingText.day(cycle.closingDate)) and is paid on \(paid)\(because). Japanese bank holidays are built in.")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let card else {
            payFrom = accounts.first { $0.kind == .bank && !$0.isArchived }?.id
            color = CardColor.allCases[accounts.filter { $0.kind == .credit }.count % CardColor.allCases.count]
            return
        }
        name = card.name
        color = AccountLook.cardColor(card)
        closingDay = card.closingDay
        paymentDay = card.paymentDay
        paymentOffset = card.paymentMonthOffset
        shift = card.holidayShift
        payFrom = card.payFromAccountID
        limit = card.creditLimit
        autoPayoff = card.autoPayoff
        reminder = card.paymentReminder
        warn = card.shortfallWarning
        archived = card.isArchived
        unpaid = max(-card.openingBalance, 0)
    }

    private func save() {
        let opening = setsOpeningAmounts
        let target: Account
        if let card {
            target = card
        } else {
            target = Account(name: name, kind: .credit, sortOrder: AccountLayout.nextSortOrder(accounts))
            context.insert(target)
        }
        if opening {
            target.openingBalance = -abs(unpaid)
            if spentSince > 0 {
                // Purchases since the last closing day belong on the bill that's building, not the closed one.
                let catchUp = Entry(kind: .adjust, amount: -spentSince, date: Date(), accountID: target.id)
                catchUp.note = "Spent before Kakeibo"
                context.insert(catchUp)
            }
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.colorKey = color.rawValue
        target.closingDay = closingDay
        target.paymentDay = paymentDay
        target.paymentMonthOffset = paymentOffset
        target.holidayShift = shift
        target.payFromAccountID = payFrom
        target.autoPayoff = autoPayoff
        target.creditLimit = max(limit, 0)
        target.paymentReminder = reminder
        target.shortfallWarning = warn
        if card != nil { target.isArchived = archived }
        context.saveAndRefresh()
        Haptics.success()
        dismiss()
    }
}
