import SwiftUI

/// A purchase's installment plan: the monthly amount, how it counts, the fee, how far along it is, and
/// "Pay off the rest".
struct InstallmentPlanCard: View {
    let plan: InstallmentPlan
    let now: Date
    let onPayOff: () -> Void

    var body: some View {
        let paid = plan.paidCount(by: now)
        let left = plan.remaining(after: now)
        CardList {
            InfoRow(title: "Plan") {
                Text("\(plan.slices.count) × \(Yen.format(plan.regularPayment))")
            }
            ListDivider(inset: 16)
            InfoRow(title: "Counts as") { Text(plan.mode.label) }
            ListDivider(inset: 16)
            InfoRow(title: "Fee") {
                Text(plan.totalFee > 0 ? Yen.format(plan.totalFee) : "None")
            }
            ListDivider(inset: 16)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(plan.isPaidOff && left == 0 ? "Paid off" : "\(paid) of \(plan.slices.count) paid")
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text(left > 0 ? "\(Yen.format(left)) left" : "Done")
                        .foregroundStyle(Palette.textSecondary)
                }
                BudgetBar(fraction: Double(paid) / Double(max(plan.slices.count, 1)), tint: Palette.accentData, height: 6)
            }
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if left > 0 && !plan.isPaidOff {
                ListDivider(inset: 16)
                Button(action: onPayOff) {
                    HStack {
                        Text("Pay Off the Rest").foregroundStyle(Palette.accentTint)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: Metrics.compactRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .monospacedDigit()
    }
}

/// When a plan is billed: charged, the first installment, and the last.
struct InstallmentTimeline: View {
    let plan: InstallmentPlan
    var now = Date()

    var body: some View {
        let first = plan.slices.first
        let last = plan.slices.last
        let payer = plan.card.payFromAccountID == nil ? "" : " · auto-paid"
        VStack(alignment: .leading, spacing: 0) {
            TimelineStep(title: BillingText.day(plan.entry.date), detail: "Charged to \(plan.card.name)", done: true, last: false)
            if let first {
                TimelineStep(title: BillingText.day(first.paymentDate),
                             detail: "Installment 1 · \(Yen.format(first.total))\(payer)",
                             done: first.paymentDate <= now, last: plan.slices.count == 1)
            }
            if let last, plan.slices.count > 1 {
                TimelineStep(title: BillingText.day(last.paymentDate),
                             detail: "Installment \(last.number) of \(plan.slices.count) · \(Yen.format(last.total))",
                             done: last.paymentDate <= now, last: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
    }
}

/// "iPhone · 3 of 24" with the monthly amount and what's left, for a card's Installments list.
struct InstallmentPlanRow: View {
    let plan: InstallmentPlan
    let lookup: Lookup
    var now = Date()

    var body: some View {
        let look = EntryPresentation(entry: plan.entry, lookup: lookup)
        KRow("\(look.title) · \(plan.paidCount(by: now)) of \(plan.slices.count)",
             subtitle: "\(Yen.format(plan.regularPayment))/mo · \(Yen.format(plan.remaining(after: now))) left",
             chevron: true) {
            look.icon()
        } trailing: {
            EmptyView()
        }
    }
}
