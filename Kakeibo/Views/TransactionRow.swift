import SwiftUI

/// What the caption under a row's amount shows.
enum RowTimeStyle {
    /// "12:41": rows already grouped by day (Activity).
    case time
    /// "12:41" today, "Yesterday", then "Nov 16" (Summary's Recent).
    case relative
}

/// One entry in a list, as on the Summary and Activity artboards: the merchant or note as the title,
/// "Category · Account" under it, and the amount with a time. Spending has no sign, income is green
/// with a plus, transfers and card payments are grey.
struct TransactionRow: View {
    let entry: Entry
    let lookup: Lookup
    var partnerName: String = SettingsKey.defaultPartnerName
    var timeStyle: RowTimeStyle = .time
    var now: Date = Date()

    private var category: BudgetCategory? { lookup.category(entry.categoryID) }
    private var account: Account? { entry.accountID.flatMap { lookup.accounts[$0] } }
    private var toAccount: Account? { entry.toAccountID.flatMap { lookup.accounts[$0] } }

    var body: some View {
        KRow(title, leading: {
            icon
        }, subtitle: {
            subtitle
        }, trailing: {
            AmountStack(amountText, color: amountColor, caption: timeText)
        })
        .accessibilityElement(children: .combine)
    }

    // MARK: Pieces

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .expense, .income:
            CategoryIcon(category: category)
        case .transfer:
            SymbolTile(symbol: "arrow.left.arrow.right", hue: .gray)
        case .payoff:
            if let card = toAccount, card.kind == .credit {
                MiniCard(color: AccountLook.cardColor(card).color, width: 32)
                    .frame(width: 32, height: 32)
            } else {
                SymbolTile(symbol: "creditcard.fill", hue: .gray)
            }
        case .settlement:
            SymbolTile(symbol: "heart.fill", hue: .pink)
        case .adjust:
            SymbolTile(symbol: "slider.horizontal.3", hue: .gray)
        }
    }

    /// Merchant, else note, else what the entry is.
    private var label: String {
        let merchant = entry.merchant.trimmingCharacters(in: .whitespaces)
        return merchant.isEmpty ? entry.note.trimmingCharacters(in: .whitespaces) : merchant
    }

    private var usesCategoryAsTitle: Bool {
        (entry.kind == .expense || entry.kind == .income) && label.isEmpty
    }

    private var title: String {
        switch entry.kind {
        case .expense:
            return label.isEmpty ? (category?.name ?? "Uncategorised") : label
        case .income:
            return label.isEmpty ? (category?.name ?? "Income") : label
        case .transfer:
            return label.isEmpty ? "Transfer" : label
        case .payoff:
            return "\(toAccount?.name ?? "Card") bill"
        case .settlement:
            return "\(partnerName) repaid"
        case .adjust:
            return "Balance adjustment"
        }
    }

    private var subtitleText: String {
        let accountName = account?.name ?? "No account"
        switch entry.kind {
        case .expense, .income:
            var parts = usesCategoryAsTitle ? [accountName] : [category?.name ?? "Uncategorised", accountName]
            if entry.isRefund { parts.insert("Refund", at: 0) }
            return parts.joined(separator: " · ")
        case .transfer, .payoff:
            return "\(accountName) → \(toAccount?.name ?? "No account")"
        case .settlement:
            return "Into \(accountName)"
        case .adjust:
            return accountName
        }
    }

    private var subtitle: some View {
        HStack(spacing: 6) {
            Text(subtitleText)
            if entry.kind == .payoff && entry.isAutoCreated {
                AutoBadge()
            }
            if entry.isSharedExpense {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                    .foregroundStyle(Hue.pink.color)
                    .accessibilityLabel("Shared with \(partnerName)")
            }
            if entry.needsReview || (entry.kind == .payoff && !entry.isConfirmed) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Palette.warning)
                    .accessibilityLabel("To review")
            }
        }
    }

    private var amountText: String {
        switch entry.kind {
        case .expense:
            return entry.isRefund ? Yen.format(entry.amount, showPlus: true) : Yen.format(entry.amount)
        case .income, .settlement, .adjust:
            return Yen.format(entry.amount, showPlus: true)
        case .transfer, .payoff:
            return Yen.format(entry.amount)
        }
    }

    private var amountColor: Color {
        switch entry.kind {
        case .income, .settlement: return Palette.positive
        case .expense: return entry.isRefund ? Palette.positive : Palette.textPrimary
        case .transfer, .payoff, .adjust: return Palette.textSecondary
        }
    }

    private var timeText: String {
        let calendar = Calendar.kakeibo
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        switch timeStyle {
        case .time:
            return time
        case .relative:
            if calendar.isDate(entry.date, inSameDayAs: now) { return time }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
               calendar.isDate(entry.date, inSameDayAs: yesterday) {
                return "Yesterday"
            }
            return entry.date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

/// Starting values for a new entry: a suggested transfer, "log again", a prefilled amount.
struct EntryDraft: Identifiable {
    let id = UUID()
    var kind: EntryKind = .expense
    var amount: Int = 0
    var accountID: UUID?
    var toAccountID: UUID?
    var categoryID: UUID?
    var note: String = ""
    var merchant: String = ""
    /// Why this draft exists, shown above the amount ("Covers the Store Card bill on Dec 2").
    var reason: String?
}
