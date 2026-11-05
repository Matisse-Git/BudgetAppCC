import SwiftData
import SwiftUI

/// First-launch checklist: today's balances, card billing dates and the default account.
struct SetupView: View {
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Fill in today's numbers. Card dates are common defaults: check them against your card's terms. Everything can be changed later.")
                        .font(.subheadline)
                }
                ForEach(accounts.filter { !$0.isArchived }) { account in
                    Section {
                        SetupAccountFields(account: account, accounts: accounts)
                    } header: {
                        Text("\(account.displayName) · \(account.kind.label)")
                    }
                }
                Section {
                    Picker("Default account", selection: $defaultAccountID) {
                        ForEach(accounts.filter { $0.tracksBalance && !$0.isArchived }) { account in
                            Text(account.displayName).tag(account.id.uuidString)
                        }
                    }
                } footer: {
                    Text("New entries start with this account. You can rename, add or archive accounts in the Accounts tab.")
                }
            }
            .navigationTitle("Set up Kakeibo")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        BillNotifications.requestPermission()
                        context.saveAndRefresh()
                        onDone()
                    }
                }
            }
        }
    }
}

private struct SetupAccountFields: View {
    @Bindable var account: Account
    let accounts: [Account]

    private var unpaid: Binding<Int> {
        Binding(get: { -account.openingBalance }, set: { account.openingBalance = -abs($0) })
    }

    var body: some View {
        if account.kind == .credit {
            AmountField(title: "Currently unpaid", value: unpaid)
            DayPicker(title: "Closing day (締め日)", day: $account.closingDay)
            DayPicker(title: "Payment day (支払日)", day: $account.paymentDay)
            Picker("Paid from", selection: $account.payFromAccountID) {
                Text("Not set (I pay it myself)").tag(UUID?.none)
                ForEach(accounts.filter { $0.holdsMoney && !$0.isArchived }) { other in
                    Text(other.displayName).tag(Optional(other.id))
                }
            }
        } else if !account.tracksBalance {
            Text("Top-ups count as spending, so there's no balance to enter.")
                .foregroundStyle(.secondary)
        } else {
            AmountField(title: "Current balance", value: $account.openingBalance, allowNegative: true)
        }
    }
}
