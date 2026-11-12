import SwiftData
import SwiftUI

enum SplitMode: String, CaseIterable, Identifiable {
    case none, half, allHers, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Just me"
        case .half: return "Split 50/50"
        case .allHers: return "All hers"
        case .custom: return "Custom share"
        }
    }
}

/// Quick Add (AddExpense and Transfer artboards). The keypad is live when the sheet opens:
/// amount → category → Save, with category and account pre-picked from history. Saving a new entry
/// closes the sheet and shows an Undo toast over the app.
struct EntryEditorView: View {
    enum Mode {
        case new
        case edit(Entry)
    }

    let mode: Mode
    /// Starting values for a new entry: its type, a suggested transfer, "log again".
    var draft: EntryDraft? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
    @Query(sort: \QuickEntry.sortOrder) private var storedQuickEntries: [QuickEntry]
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""
    @AppStorage(SettingsKey.partnerName) private var partnerName = SettingsKey.defaultPartnerName
    @AppStorage(SettingsKey.suggestCategory) private var suggests = true

    @State private var kind: EntryKind = .expense
    @State private var amount = 0
    @State private var accountID: UUID?
    @State private var toAccountID: UUID?
    @State private var categoryID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var merchant = ""
    @State private var split: SplitMode = .none
    @State private var customShare = 0
    @State private var isRefund = false
    @State private var installmentCount = 0
    @State private var installmentMode: InstallmentMode = .monthly
    @State private var installmentFee = -1
    /// Transfer fee: shown once "+ Fee" is tapped; taken from the amount, or added on top of it.
    @State private var showingFee = false
    @State private var transferFee = 0
    @State private var feeOnTop = false
    @State private var settingInstallments = false
    @State private var reason: String?
    @State private var loaded = false
    /// Set once the starting values are in, so filling them in doesn't vibrate or re-suggest.
    @State private var ready = false
    @State private var confirmDelete = false
    @State private var pickingDate = false
    @State private var pickingCategory = false
    /// The quick entry whose chip filled in the form; saved on the entry for the widget's count.
    @State private var quickEntryID: UUID?
    @State private var savingAsQuickEntry = false
    @Environment(SavedToastCenter.self) private var toasts: SavedToastCenter?

    private var editing: Entry? {
        if case .edit(let entry) = mode { return entry }
        return nil
    }

    // MARK: Choices

    /// Accounts you can pay with (or, for income, receive into).
    private var payAccounts: [Account] {
        accounts.filter { account in
            if account.id == editing?.accountID { return true }
            guard !account.isArchived else { return false }
            return kind == .income ? account.holdsMoney : account.tracksBalance
        }
    }

    private var transferChoices: [Account] {
        accounts.filter { !$0.isArchived || $0.id == editing?.accountID || $0.id == editing?.toAccountID }
    }

    private var categoryKind: CategoryKind { kind == .income ? .income : .expense }

    private var allCategories: [BudgetCategory] {
        categories.filter { $0.kind == categoryKind && (!$0.isArchived || $0.id == categoryID) }
    }

    /// Quick-entry chips, on a new expense only.
    private var quickEntries: [QuickEntry] {
        guard editing == nil, kind == .expense else { return [] }
        return QuickEntries.sorted(storedQuickEntries)
    }

    private var partnerShare: Int {
        guard kind == .expense, !isRefund else { return 0 }
        switch split {
        case .none: return 0
        case .half: return amount / 2
        case .allHers: return amount
        case .custom: return min(max(customShare, 0), amount)
        }
    }

    /// The selected account when it's a credit card: only card purchases can be paid in installments.
    private var selectedCard: Account? {
        accounts.first { $0.id == accountID && $0.kind == .credit }
    }

    private var offersInstallments: Bool {
        kind == .expense && !isRefund && selectedCard != nil
    }

    /// Billing has started on this purchase's plan: it can only be paid off now (from its detail page).
    private var installmentsLocked: Bool {
        guard let entry = editing, entry.isInstallment, let card = selectedCard,
              let plan = InstallmentPlan(entry: entry, card: card) else { return false }
        return plan.isLocked(now: Date())
    }

    private var installmentSummary: String? {
        guard offersInstallments, installmentCount >= 2, let card = selectedCard else { return nil }
        let fee = installmentFee >= 0 ? installmentFee
            : Installments.fee(principal: amount, months: installmentCount, annualRate: card.installmentFeeRate)
        let principal = Installments.split(amount, into: installmentCount)
        let fees = Installments.split(fee, into: installmentCount)
        let monthly = principal.count > 1 ? principal[1] + fees[1] : (principal.first ?? 0)
        return "\(installmentCount) months · \(Yen.format(monthly))/mo · \(installmentMode.label)"
    }

    /// What leaves, the fee and what arrives, for a transfer.
    private var transfer: TransferAmounts {
        TransferAmounts(typed: amount, fee: kind == .transfer && showingFee ? transferFee : 0, onTop: feeOnTop)
    }

    /// The last fee paid between the chosen accounts, offered as a one-tap suggestion.
    private var lastFee: (fee: Int, onTop: Bool)? {
        Ledger(accounts: accounts, entries: entries).lastTransferFee(from: accountID, to: toAccountID, excluding: editing?.id)
    }

    private var canSave: Bool {
        guard amount > 0 else { return false }
        if kind == .transfer {
            return accountID != nil && toAccountID != nil && accountID != toAccountID && transfer.isValid
        }
        return categoryID != nil
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 14)
                .padding(.horizontal, 4)
            amountDisplay
                .padding(.top, 14)
            ScrollView(showsIndicators: false) {
                middle
                    .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            KeypadView(amount: $amount, canSave: canSave, onSave: save)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .background(Palette.sheet.ignoresSafeArea())
        // The note's keyboard covers the keypad instead of squashing the sheet.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.sheet)
        .sheet(isPresented: $pickingDate) {
            EntryDateSheet(date: $date)
        }
        .sheet(isPresented: $settingInstallments) {
            if let card = selectedCard {
                InstallmentSheet(amount: amount, card: card, purchaseDate: date, count: $installmentCount,
                                 mode: $installmentMode, feeOverride: $installmentFee)
            }
        }
        .sheet(isPresented: $pickingCategory) {
            CategoryPickerSheet(categories: allCategories, selection: $categoryID)
        }
        .sheet(isPresented: $savingAsQuickEntry) {
            if let entry = editing {
                QuickEntryEditView(draft: QuickEntryDraft(entry: entry, categories: categories))
            }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteEntry)
        }
        .onAppear(perform: load)
        .onChange(of: kind) { _, newKind in kindChanged(to: newKind) }
        .sensoryFeedback(.firmSelection, trigger: kind) { _, _ in ready }
        .sensoryFeedback(.firmSelection, trigger: split) { _, _ in ready }
        .sensoryFeedback(.firmSelection, trigger: isRefund) { _, _ in ready }
        .sensoryFeedback(.firmSelection, trigger: accountID) { _, _ in ready }
        .sensoryFeedback(.firmSelection, trigger: toAccountID) { _, _ in ready }
        .sensoryFeedback(.firmSelection, trigger: feeOnTop) { _, _ in ready }
        .sensoryFeedback(.firmSelection, trigger: showingFee) { _, _ in ready }
        .sensoryFeedback(.firmSelection, trigger: categoryID) { _, _ in ready }
        .sensoryFeedback(.firmSelection, trigger: quickEntryID) { _, new in ready && new != nil }
        .sensoryFeedback(.firmSelection, trigger: Calendar.kakeibo.startOfDay(for: date)) { _, _ in ready }
    }

    // MARK: Header and amount

    private var header: some View {
        HStack(spacing: 10) {
            CircleIconButton(symbol: "xmark", label: "Close") { dismiss() }
            Picker("Entry type", selection: $kind) {
                Text("Expense").tag(EntryKind.expense)
                Text("Income").tag(EntryKind.income)
                Text("Transfer").tag(EntryKind.transfer)
            }
            .pickerStyle(.segmented)
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            if kind == .expense {
                Picker("Split with \(partnerName)", selection: $split) {
                    ForEach(SplitMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("Refund", isOn: $isRefund)
                if offersInstallments {
                    if installmentsLocked {
                        Text("Installments are fixed once billing starts")
                    } else {
                        Button {
                            settingInstallments = true
                        } label: {
                            Label(installmentCount >= 2 ? "Change installments…" : "Pay in installments…",
                                  systemImage: "calendar.badge.clock")
                        }
                    }
                }
            }
            if kind == .transfer {
                Button {
                    swapAccounts()
                } label: {
                    Label("Swap accounts", systemImage: "arrow.up.arrow.down")
                }
            }
            if let entry = editing, entry.kind == .expense, !entry.isRefund {
                Button {
                    savingAsQuickEntry = true
                } label: {
                    Label("Save as Quick Entry…", systemImage: "bolt")
                }
            }
            if editing != nil {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            CircleIconLabel(symbol: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(kind == .expense ? "More options: split, refund" : "More options")
    }

    private var amountDisplay: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kind == .income ? "+¥" : "¥")
                    .font(.kAmountCurrency)
                    .foregroundStyle(Palette.textSecondary)
                Text(Yen.digits(amount))
                    .font(.kAmountEntry)
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundStyle(amount == 0 ? Palette.textSecondary : (kind == .income ? Palette.positive : Palette.textPrimary))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(height: 72)
            if let reason, kind == .transfer {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                    Text(reason)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.positive)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Palette.positive.opacity(0.14)))
            } else if kind == .transfer && transfer.fee > 0 && amount > 0 {
                Text(feeOnTop
                     ? "\(Yen.format(transfer.sent)) leaves · \(Yen.format(transfer.fee)) fee"
                     : "\(Yen.format(transfer.received)) arrives · \(Yen.format(transfer.fee)) fee")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(transfer.isValid ? Palette.textSecondary : Palette.negativeText)
                    .monospacedDigit()
            } else if let installmentSummary {
                Button {
                    if !installmentsLocked { settingInstallments = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock").font(.caption.weight(.bold))
                        Text(installmentSummary)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accentSoftText)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Palette.accentSoftFill))
                }
                .buttonStyle(.plain)
                .monospacedDigit()
            } else if partnerShare > 0 {
                Text("You \(Yen.format(amount - partnerShare)) · \(partnerName) \(Yen.format(partnerShare))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Hue.pink.color)
                    .monospacedDigit()
            } else if isRefund && kind == .expense {
                Text("Refund: reduces spending")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.positive)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Amount \(Yen.format(amount))")
    }

    // MARK: Middle

    @ViewBuilder
    private var middle: some View {
        VStack(alignment: .leading, spacing: 0) {
            if kind == .transfer {
                transferCard
                    .padding(.top, 16)
                feeSection
                    .padding(.top, 10)
                chips
                    .padding(.top, 14)
            } else {
                if !quickEntries.isEmpty {
                    quickEntryChips
                        .padding(.top, 10)
                }
                chips
                    .padding(.top, 10)
                if kind == .expense && split == .custom && !isRefund {
                    customShareField
                        .padding(.top, 10)
                }
                fieldLabel(kind == .income ? "Received in" : "Paid with")
                    .padding(.top, 18)
                accountChips
                    .padding(.top, 8)
                fieldLabel("Category")
                    .padding(.top, 16)
                categoryGrid
                    .padding(.top, 8)
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 4)
    }

    private var dateLabel: String {
        let calendar = Calendar.kakeibo
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today, \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    private var chips: some View {
        HStack(spacing: 8) {
            Button {
                pickingDate = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").foregroundStyle(Palette.accentTint)
                    Text(dateLabel).lineLimit(1)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(Palette.chipFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Date \(dateLabel)")

            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .foregroundStyle(Palette.accentTint)
                    .accessibilityHidden(true)
                TextField("Add a note", text: $note)
                    .submitLabel(.done)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minWidth: 90, maxWidth: 170)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(Palette.chipFill))
        }
        .frame(maxWidth: .infinity)
    }

    private var customShareField: some View {
        HStack {
            Text("\(partnerName)'s share")
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            YenField(placeholder: "¥0", value: $customShare)
                .frame(maxWidth: 140)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: Metrics.sheetGroupRadius, style: .continuous).fill(Palette.sheetRow))
        .padding(.horizontal, 4)
    }

    /// Your quick entries. A tap fills in amount, category, account, split and note; then Save.
    private var quickEntryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickEntries) { item in
                    Button {
                        apply(item)
                    } label: {
                        QuickEntryChip(quickEntry: item, selected: item.id == quickEntryID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -12)
    }

    private var accountChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(payAccounts) { account in
                        Button {
                            accountID = account.id
                        } label: {
                            AccountChip(account: account, selected: account.id == accountID)
                        }
                        .buttonStyle(.plain)
                        .id(account.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -12)
            .onAppear {
                if let accountID { proxy.scrollTo(accountID, anchor: .center) }
            }
        }
    }

    private var categoryGrid: some View {
        let showsAll = allCategories.count > 8
        let tiles = Suggestions.tiles(kind: categoryKind, selected: categoryID, limit: showsAll ? 7 : 8,
                                      entries: entries, categories: allCategories)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 8) {
            ForEach(tiles) { category in
                Button {
                    categoryID = category.id
                } label: {
                    CategoryChoice(category: category, selected: category.id == categoryID)
                }
                .buttonStyle(.plain)
            }
            if showsAll {
                Button {
                    pickingCategory = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.chipFill))
                        Text("All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All categories")
            }
        }
    }

    // MARK: Transfer

    private var transferCard: some View {
        let ledger = Ledger(accounts: accounts, entries: entries)
        return VStack(spacing: 0) {
            transferRow("From", selection: $accountID, delta: -transfer.sent, ledger: ledger)
            Rectangle().fill(Palette.separator).frame(height: 0.5).padding(.leading, 64)
            transferRow("To", selection: $toAccountID, delta: transfer.received, ledger: ledger)
        }
        .background(RoundedRectangle(cornerRadius: Metrics.sheetGroupRadius, style: .continuous).fill(Palette.sheetRow))
        .overlay {
            Button {
                swapAccounts()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Palette.controlFill).background(Circle().fill(Palette.sheetRow)))
                    .overlay(Circle().stroke(Palette.sheetRow, lineWidth: 4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Swap accounts")
        }
        .padding(.horizontal, 4)
    }

    /// "+ Fee" (and last time's fee between these accounts) until a fee is added; then the fee and
    /// whether it's taken from the amount or added on top.
    private var feeSection: some View {
        let suggestion = lastFee
        return VStack(spacing: 8) {
            if showingFee {
                feeCard
                if transferFee == 0, let suggestion {
                    feeSuggestionChip(suggestion)
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        feeOnTop = suggestion?.onTop ?? false
                        showingFee = true
                    } label: {
                        feeChipLabel("Fee", symbol: "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a fee")
                    if let suggestion {
                        feeSuggestionChip(suggestion)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var feeCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Fee")
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                YenField(placeholder: "¥0", value: $transferFee)
                    .frame(maxWidth: 140)
                Button {
                    removeFee()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove fee")
            }
            .frame(height: 44)
            Picker("How the fee is paid", selection: $feeOnTop) {
                Text("Taken from amount").tag(false)
                Text("Added on top").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 12)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: Metrics.sheetGroupRadius, style: .continuous).fill(Palette.sheetRow))
        .padding(.horizontal, 4)
    }

    private func feeSuggestionChip(_ suggestion: (fee: Int, onTop: Bool)) -> some View {
        Button {
            transferFee = suggestion.fee
            feeOnTop = suggestion.onTop
            showingFee = true
        } label: {
            feeChipLabel("\(Yen.format(suggestion.fee)), like last time", symbol: "clock.arrow.circlepath")
        }
        .buttonStyle(.plain)
    }

    private func feeChipLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Palette.accentTint)
            Text(title).lineLimit(1).monospacedDigit()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Palette.chipFill))
    }

    private func removeFee() {
        showingFee = false
        transferFee = 0
    }

    private func transferRow(_ label: String, selection: Binding<UUID?>, delta: Int, ledger: Ledger) -> some View {
        let account = accounts.first { $0.id == selection.wrappedValue }
        return Menu {
            Picker(label, selection: selection) {
                ForEach(transferChoices) { choice in
                    Text(choice.name).tag(Optional(choice.id))
                }
            }
        } label: {
            HStack(spacing: 12) {
                AccountIcon(account: account, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Text(account?.name ?? "Choose an account")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let account, account.tracksBalance {
                    let now = ledger.balance(of: account, before: Date())
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Yen.format(now))
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                        Text("→ \(Yen.format(now + delta))")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(delta > 0 && amount > 0 ? Palette.positive : Palette.textPrimary)
                    }
                    .monospacedDigit()
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Loading

    private func defaultAccount(for kind: EntryKind) -> UUID? {
        let preferred = UUID(uuidString: defaultAccountID)
        let options = accounts.filter { account in
            guard !account.isArchived else { return false }
            return kind == .income ? account.holdsMoney : account.tracksBalance
        }
        return options.first { $0.id == preferred }?.id ?? options.first?.id
    }

    private func suggestedCategory(for kind: EntryKind) -> UUID? {
        guard suggests else { return nil }
        return Suggestions.category(kind: kind, at: date, entries: entries, categories: categories)
    }

    private func suggestedAccount(for kind: EntryKind, category: UUID?) -> UUID? {
        let learned = suggests ? Suggestions.account(forCategory: category, kind: kind, entries: entries, accounts: accounts) : nil
        return learned ?? defaultAccount(for: kind)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        Haptics.prepare()
        defer { DispatchQueue.main.async { ready = true } }
        if let entry = editing {
            kind = entry.kind
            amount = entry.amount
            accountID = entry.accountID
            toAccountID = entry.toAccountID
            categoryID = entry.categoryID
            date = entry.date
            note = entry.note
            merchant = entry.merchant
            isRefund = entry.isRefund
            installmentCount = entry.installmentCount
            installmentMode = entry.installmentMode
            installmentFee = entry.installmentFeeOverride
            split = SplitMode.matching(share: entry.partnerShare, amount: entry.amount)
            if split == .custom { customShare = entry.partnerShare }
            if entry.feePaid > 0 {
                showingFee = true
                transferFee = entry.feePaid
                feeOnTop = entry.transferFeeOnTop
                amount = TransferAmounts.typed(for: entry)
            }
            return
        }
        let start = draft ?? EntryDraft()
        kind = start.kind
        amount = start.amount
        note = start.note
        merchant = start.merchant
        reason = start.reason
        if start.kind == .transfer && start.transferFee > 0 {
            showingFee = true
            transferFee = start.transferFee
            feeOnTop = start.transferFeeOnTop
        }
        if start.kind == .transfer {
            accountID = start.accountID ?? defaultAccount(for: .expense)
            toAccountID = start.toAccountID ?? transferChoices.first { $0.id != accountID && $0.holdsMoney }?.id
        } else {
            categoryID = start.categoryID ?? suggestedCategory(for: start.kind)
            accountID = start.accountID ?? suggestedAccount(for: start.kind, category: categoryID)
        }
        if DemoMode.isOn && draft == nil { amount = 980 }
    }

    /// Fills the form from a quick entry. The date stays as it is.
    private func apply(_ item: QuickEntry) {
        let card = item.card
        amount = card.amount
        categoryID = card.categoryID
        if let id = QuickEntries.accountID(for: card, accounts: accounts, defaultAccountID: UUID(uuidString: defaultAccountID)) {
            accountID = id
        }
        note = card.name
        merchant = card.merchant
        isRefund = false
        installmentCount = 0
        split = SplitMode.matching(share: card.partnerShare, amount: card.amount)
        customShare = card.partnerShare
        quickEntryID = card.id
    }

    private func kindChanged(to newKind: EntryKind) {
        guard ready else { return }
        switch newKind {
        case .transfer:
            if toAccountID == nil || toAccountID == accountID {
                toAccountID = transferChoices.first { $0.id != accountID && $0.holdsMoney }?.id
            }
        case .expense, .income:
            if let current = categoryID, categories.first(where: { $0.id == current })?.kind == categoryKind {
                break
            }
            categoryID = suggestedCategory(for: newKind)
            if let current = accountID, payAccounts.contains(where: { $0.id == current }) {
                break
            }
            accountID = suggestedAccount(for: newKind, category: categoryID)
        default:
            break
        }
    }

    // MARK: Saving

    private func save() {
        guard canSave else { return }
        let isNew = editing == nil
        let entry = editing ?? Entry(kind: kind, amount: amount)
        let transfer = self.transfer
        entry.kind = kind
        entry.amount = kind == .transfer ? transfer.sent : amount
        entry.transferFee = kind == .transfer ? transfer.fee : 0
        entry.transferFeeOnTop = kind == .transfer && transfer.fee > 0 && feeOnTop
        entry.date = date
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.merchant = merchant
        entry.accountID = accountID
        entry.toAccountID = kind == .transfer ? toAccountID : nil
        entry.categoryID = kind == .transfer ? nil : categoryID
        entry.isRefund = kind == .expense && isRefund
        entry.partnerShare = partnerShare
        entry.needsReview = false
        if !installmentsLocked {
            let installments = offersInstallments && installmentCount >= 2
            entry.installmentCount = installments ? installmentCount : 0
            entry.installmentMode = installmentMode
            entry.installmentFeeOverride = installments ? installmentFee : -1
            if !installments { entry.installmentPaidOffAt = nil }
        }
        if isNew {
            if kind == .expense { entry.quickEntryID = quickEntryID }
            context.insert(entry)
        }
        context.saveAndRefresh()
        let limitNote = limitCrossing(entry)
        if endsOverBudget(entry) || limitNote != nil {
            Haptics.warning()
        } else {
            Haptics.success()
        }
        // The sheet closes on Save; the Undo toast shows over the app for a new entry.
        if isNew {
            let message = limitNote.map { "Saved \(Yen.format(entry.amount)) · \($0)" } ?? toastMessage(for: entry)
            toasts?.show(message, entry: entry)
        }
        dismiss()
    }

    private func toastMessage(for entry: Entry) -> String {
        let name: (UUID?) -> String = { id in self.accounts.first { $0.id == id }?.name ?? "No account" }
        if entry.kind == .transfer {
            let fee = entry.feePaid > 0 ? " · \(Yen.format(entry.feePaid)) fee" : ""
            return "Saved \(Yen.format(entry.amount)) · \(name(entry.accountID)) → \(name(entry.toAccountID))\(fee)"
        }
        let category = categories.first { $0.id == entry.categoryID }?.name ?? "Uncategorised"
        if entry.isInstallment {
            return "Saved \(Yen.format(entry.amount)) · \(entry.installmentCount) months · \(category)"
        }
        return "Saved \(Yen.format(entry.amount)) · \(category) · \(name(entry.accountID))"
    }

    /// "Olive now at 46% of its limit" when this purchase took a card past its limit alert.
    private func limitCrossing(_ entry: Entry) -> String? {
        guard entry.kind == .expense, !entry.isRefund,
              let card = accounts.first(where: { $0.id == entry.accountID }), card.kind == .credit,
              card.creditLimit > 0, card.limitAlertPercent > 0 else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let ledger = Ledger(accounts: accounts, categories: categories, entries: all)
        let now = max(Date(), entry.date.addingTimeInterval(1))
        guard let usage = card.limitUsage(ledger: ledger, now: now), CreditLimits.crosses(usage, adding: entry.amount) else { return nil }
        return "\(card.name) now at \(usage.percent)% of its limit"
    }

    /// A spending entry that leaves its category over budget gets a warning buzz instead of success.
    private func endsOverBudget(_ entry: Entry) -> Bool {
        guard entry.kind == .expense, !entry.isRefund, entry.myShare > 0 else { return false }
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        return Ledger(accounts: accounts, categories: categories, entries: all)
            .isOverBudget(categoryID: entry.categoryID, inMonthOf: entry.date)
    }

    private func swapAccounts() {
        let from = accountID
        accountID = toAccountID
        toAccountID = from
    }

    private func deleteEntry() {
        guard let entry = editing else { return }
        context.delete(entry)
        context.saveAndRefresh()
        Haptics.warning()
        dismiss()
    }
}

// MARK: - Pieces

/// 44 pt round button on a sheet (close, more).
struct CircleIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleIconLabel(symbol: symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct CircleIconLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Palette.textPrimary)
            .frame(width: Metrics.buttonHeight, height: Metrics.buttonHeight)
            .background(Circle().fill(Palette.controlFill))
            .contentShape(Circle())
    }
}

/// An account in the "Paid with" row: its icon or mini card and name; ringed in indigo when picked.
struct AccountChip: View {
    let account: Account
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            if account.kind == .credit {
                MiniCard(color: AccountLook.cardColor(account).color, width: 24)
            } else {
                let look = AccountLook.of(account)
                SymbolTile(symbol: look.symbol, hue: look.hue, size: 24, circle: true)
            }
            Text(account.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.leading, account.kind == .credit ? 8 : 6)
        .padding(.trailing, 13)
        .frame(height: 36)
        .background(Capsule().fill(selected ? Palette.accentTint.opacity(0.24) : Palette.chipFill))
        .overlay(Capsule().strokeBorder(selected ? Palette.accentTint : Color.clear, lineWidth: 1.5))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A quick entry in the add sheet: its emoji, name and amount; ringed in indigo once used.
struct QuickEntryChip: View {
    let quickEntry: QuickEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(quickEntry.emoji)
            Text(quickEntry.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(Yen.format(quickEntry.amount))
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 13)
        .frame(height: 36)
        .background(Capsule().fill(selected ? Palette.accentTint.opacity(0.24) : Palette.chipFill))
        .overlay(Capsule().strokeBorder(selected ? Palette.accentTint : Color.clear, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quick entry \(quickEntry.name), \(Yen.format(quickEntry.amount))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// A category tile in the add sheet: filled with its colour when picked.
struct CategoryChoice: View {
    let category: BudgetCategory
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            CategoryIcon(category: category, size: 48, selected: selected)
            Text(category.name)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Every category of a kind, for the "All" tile.
struct CategoryPickerSheet: View {
    let categories: [BudgetCategory]
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(categories) { category in
                Button {
                    selection = category.id
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        CategoryIcon(category: category)
                        Text(category.name).foregroundStyle(Palette.textPrimary)
                        Spacer()
                        if selection == category.id {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.accentTint)
                        }
                    }
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Date and time of an entry.
struct EntryDateSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker("Date and time", selection: $date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
            }
            .navigationTitle("Date & Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Now") { date = Date() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Simple form for card payoffs, repayments and balance adjustments.
struct EntryDetailForm: View {
    @Bindable var entry: Entry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @State private var confirmDelete = false

    private var moneyAccounts: [Account] { accounts.filter { $0.holdsMoney || $0.id == entry.accountID } }
    private var creditAccounts: [Account] { accounts.filter { $0.kind == .credit || $0.id == entry.toAccountID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Type", value: entry.kind.label)
                    AmountField(title: entry.kind == .adjust ? "Change" : "Amount", value: $entry.amount, allowNegative: entry.kind == .adjust)
                    DatePicker("Date", selection: $entry.date)
                }
                Section {
                    switch entry.kind {
                    case .payoff:
                        accountPicker("Paid from", selection: $entry.accountID, options: moneyAccounts)
                        accountPicker("Card", selection: $entry.toAccountID, options: creditAccounts)
                    case .settlement:
                        accountPicker("Received in", selection: $entry.accountID, options: moneyAccounts)
                    default:
                        accountPicker("Account", selection: $entry.accountID, options: accounts)
                    }
                }
                if entry.kind == .payoff {
                    Section {
                        Toggle("Confirmed", isOn: $entry.isConfirmed)
                            .sensoryFeedback(trigger: entry.isConfirmed) { _, confirmed in
                                confirmed ? SensoryFeedback.success : SensoryFeedback.firmSelection
                            }
                    } footer: {
                        Text("Tick this once you've seen the real debit. Unconfirmed payoffs still move the money.")
                    }
                }
                Section {
                    TextField("Note", text: $entry.note)
                }
                Section {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(entry.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        entry.needsReview = false
                        context.saveAndRefresh()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    context.saveAndRefresh()
                    Haptics.warning()
                    dismiss()
                }
            }
        }
    }

    private func accountPicker(_ title: String, selection: Binding<UUID?>, options: [Account]) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(UUID?.none)
            ForEach(options) { account in
                Text(account.displayName).tag(Optional(account.id))
            }
        }
    }
}
