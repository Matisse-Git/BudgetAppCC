import SwiftUI

/// Setting up 分割払い for a card purchase: how many months, how it counts toward budgets, and the fee
/// (the card's rate, or an exact amount such as ¥0 for an interest-free campaign).
struct InstallmentSheet: View {
    let amount: Int
    let card: Account
    let purchaseDate: Date
    @Binding var count: Int
    @Binding var mode: InstallmentMode
    @Binding var feeOverride: Int

    @Environment(\.dismiss) private var dismiss
    @State private var months = 24
    @State private var countsAs: InstallmentMode = .monthly
    @State private var exactFee = false
    @State private var fee = 0
    @State private var loaded = false

    private var cardFee: Int {
        Installments.fee(principal: amount, months: months, annualRate: card.installmentFeeRate)
    }

    private var totalFee: Int { exactFee ? fee : cardFee }

    private var monthChoices: [Int] {
        Array(Set(Installments.standardCounts + [months])).sorted()
    }

    var body: some View {
        let principals = Installments.split(amount, into: months)
        let fees = Installments.split(totalFee, into: months)
        let firstTotal = (principals.first ?? 0) + (fees.first ?? 0)
        let regularTotal = principals.count > 1 ? principals[1] + fees[1] : firstTotal
        let first = Billing.cycle(containing: purchaseDate, rule: card.billingRule)
        let last = Billing.shifted(first, by: months - 1, rule: card.billingRule)
        NavigationStack {
            Form {
                Section {
                    Picker("Months", selection: $months) {
                        ForEach(monthChoices, id: \.self) { count in
                            Text("\(count) months").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    Stepper("Custom: \(months) months", value: $months, in: 2...Installments.maxCount)
                } header: {
                    Text("Pay \(Yen.format(amount)) over")
                }

                Section {
                    Picker("Counts as", selection: $countsAs) {
                        ForEach(InstallmentMode.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Counts toward budgets")
                } footer: {
                    Text(countsAs.detail)
                }

                Section {
                    LabeledContent("Card rate", value: card.installmentFeeRate > 0
                                   ? "\(PercentField.display(card.installmentFeeRate))% a year"
                                   : "None set")
                    Toggle("Exact fee for this purchase", isOn: $exactFee)
                    if exactFee {
                        LabeledContent("Total fee") {
                            YenField(placeholder: "¥0", value: $fee)
                        }
                    }
                } header: {
                    Text("Fee")
                } footer: {
                    Text(feeFooter)
                }

                Section("Plan") {
                    LabeledContent("Each month", value: Yen.format(regularTotal))
                    if firstTotal != regularTotal {
                        LabeledContent("First month", value: Yen.format(firstTotal))
                    }
                    LabeledContent("First payment", value: BillingText.day(first.paymentDate))
                    LabeledContent("Last payment", value: BillingText.day(last.paymentDate))
                    LabeledContent("Total with fees", value: Yen.format(amount + totalFee))
                }
                .monospacedDigit()

                if count >= 2 {
                    Section {
                        Button("Pay in full instead", role: .destructive) {
                            count = 0
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Pay in Installments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        count = months
                        mode = countsAs
                        feeOverride = exactFee ? max(fee, 0) : -1
                        Haptics.selection()
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.firmSelection, trigger: months)
            .sensoryFeedback(.firmSelection, trigger: countsAs)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                months = count >= 2 ? count : 24
                countsAs = mode
                exactFee = feeOverride >= 0
                fee = max(feeOverride, 0)
            }
        }
        .presentationDetents([.large])
    }

    private var feeFooter: String {
        if exactFee { return "Copy the fee from your card's confirmation, or ¥0 for an interest-free plan." }
        if months <= 2 { return "Two installments are free." }
        if card.installmentFeeRate <= 0 { return "No rate is set for \(card.name), so there's no fee. Set one in the card's settings, or enter the exact fee." }
        return "\(Yen.format(cardFee)) at \(PercentField.display(card.installmentFeeRate))% a year, charged a slice on each bill. It counts as spending in Card fees."
    }
}
