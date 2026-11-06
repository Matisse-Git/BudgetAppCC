import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// First run (Welcome and SetupAccounts artboards): welcome, the places you pay from, then optional
/// monthly budgets.
struct OnboardingView: View {
    var onDone: () -> Void

    enum Step: Hashable {
        case accounts, budgets
    }

    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(start: { path.append(.accounts) }, restored: onDone)
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .accounts:
                        SetupAccountsView { path.append(.budgets) }
                    case .budgets:
                        SetupBudgetsView(done: finish)
                    }
                }
        }
        .tint(Palette.accentTint)
    }

    private func finish() {
        BillNotifications.requestPermission()
        onDone()
    }
}

struct WelcomeView: View {
    let start: () -> Void
    let restored: () -> Void

    @Environment(\.modelContext) private var context
    @State private var importing = false
    @State private var pendingImport: Data?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.accentFill)
                .frame(width: 88, height: 88)
                .overlay(
                    Image(systemName: "yensign")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                )
                .accessibilityLabel("Kakeibo app icon")
            Text("家計簿")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 20)
                .accessibilityHidden(true)
            Text("Welcome to Kakeibo")
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, 2)
            Text("A household ledger for life in Japan.")
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 22) {
                feature("bolt.fill", "Log in seconds", "Type the amount, tap a category, done. Your usual account is already picked.")
                feature("creditcard.fill", "Card bills, sorted", "Closing and payment days for every card, and a warning before an account runs short.")
                feature("lock.fill", "Stays on this iPhone", "No sign-up and no bank connections. Nothing leaves your device.")
            }
            .padding(.top, 36)
            Spacer(minLength: 24)
            Button("Get Started", action: start)
                .buttonStyle(PillButtonStyle(height: 50))
            Button("Restore from a Backup") { importing = true }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .kScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingImport = try? Data(contentsOf: url)
            if pendingImport == nil { message = "Couldn't read that file." }
        }
        .alert("Restore this backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Restore") {
                if let data = pendingImport {
                    do {
                        try Backup.restore(from: data, into: context)
                        Maintenance.run(context, autoPayoffs: false)
                        Haptics.success()
                        restored()
                    } catch {
                        message = "Restore failed: \(error.localizedDescription)"
                    }
                }
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("The sample accounts are replaced by what's in the backup.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Palette.accentTint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Step 1: every place you pay from, with today's balances.
struct SetupAccountsView: View {
    let next: () -> Void

    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var entries: [Entry]
    @State private var editing: Account?
    @State private var creatingKind: AccountKind?
    @State private var creatingCard = false

    var body: some View {
        let ledger = Ledger(accounts: accounts, entries: entries)
        let active = AccountLayout.sorted(accounts.filter { !$0.isArchived })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add your money")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.textPrimary)
                Text("Every place you pay from. Rough balances are fine; you can correct them any time.")
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 4)
                if !active.isEmpty {
                    CardList {
                        ForEach(Array(active.enumerated()), id: \.element.id) { index, account in
                            if index > 0 { ListDivider(inset: account.kind == .credit ? 64 : 60) }
                            Button {
                                editing = account
                            } label: {
                                KRow(account.name, subtitle: detail(account), chevron: true) {
                                    AccountIcon(account: account)
                                } trailing: {
                                    if account.kind == .credit {
                                        AmountStack(Yen.format(max(-ledger.balance(of: account), 0)), caption: "owed")
                                    } else if account.tracksBalance {
                                        Text(Yen.format(ledger.balance(of: account)))
                                            .font(.body.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(Palette.textPrimary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 20)
                }
                Text("Add another")
                    .font(.title3.bold())
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, Metrics.sectionSpacing)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    addTile("Bank account", "Salary, savings", symbol: "building.columns.fill", hue: .blue) { creatingKind = .bank }
                    addTile("Prepaid wallet", "Transit IC, QR pay, e-money", symbol: "wave.3.right", hue: .green) { creatingKind = .topUp }
                    addTile("Cash", "Wallet, coin purse", symbol: "banknote.fill", hue: .tan) { creatingKind = .cash }
                    addTile("Credit card", "Closing & payment days", symbol: "creditcard.fill", hue: .indigo) { creatingCard = true }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
        }
        .kScreenBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button("Continue", action: next)
                    .buttonStyle(PillButtonStyle(height: 50))
                Text("Next: monthly budgets, which you can skip.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(Palette.background)
        }
        .navigationTitle("Step 1 of 2")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { account in
            if account.kind == .credit {
                CardSetupView(card: account)
            } else {
                AccountEditView(account: account)
            }
        }
        .sheet(item: $creatingKind) { kind in
            AccountEditView(account: nil, initialKind: kind)
        }
        .sheet(isPresented: $creatingCard) {
            CardSetupView(card: nil)
        }
    }

    private func detail(_ account: Account) -> String {
        switch account.kind {
        case .credit: return BillingText.rule(account)
        case .bank: return "Bank account"
        case .topUp: return account.tracksBalance ? "Prepaid wallet" : "Top-ups count as spending"
        case .cash: return "Cash"
        }
    }

    private func addTile(_ title: String, _ detail: String, symbol: String, hue: Hue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                SymbolTile(symbol: symbol, hue: hue, size: 32, circle: hue != .indigo)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
        }
        .buttonStyle(.plain)
    }
}

/// Step 2: a monthly budget for each category, all optional.
struct SetupBudgetsView: View {
    let done: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]

    var body: some View {
        Form {
            Section {
                ForEach(categories.filter { $0.kind == .expense && !$0.isArchived }) { category in
                    LabeledContent {
                        YenField(placeholder: "No budget", value: Binding(
                            get: { category.monthlyBudget },
                            set: { category.monthlyBudget = max($0, 0) }
                        ))
                    } label: {
                        HStack(spacing: 10) {
                            CategoryIcon(category: category, size: 28)
                            Text(category.name)
                        }
                    }
                }
            } header: {
                Text("Monthly budgets")
            } footer: {
                Text("Leave a category at 0 for no budget; its spending still counts. Change these any time in Budgets › Edit.")
            }
        }
        .scrollContentBackground(.hidden)
        .kScreenBackground()
        .navigationTitle("Step 2 of 2")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip", action: done)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    context.saveAndRefresh()
                    done()
                }
            }
        }
    }
}
