import SwiftUI
import UIKit

extension Color {
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let chip = Color(uiColor: .secondarySystemBackground)
    static let key = Color(uiColor: .tertiarySystemFill)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.card))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// Share sheet for exported files.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ProgressBar: View {
    let fraction: Double
    let isOver: Bool

    private var color: Color {
        if isOver { return .red }
        if fraction > 0.85 { return .orange }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.key)
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
    }
}

/// Whole-yen number field.
struct AmountField: View {
    let title: String
    @Binding var value: Int
    var allowNegative = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("¥0", value: $value, format: .number)
                .keyboardType(allowNegative ? .numbersAndPunctuation : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
    }
}

struct DayPicker: View {
    let title: String
    @Binding var day: Int

    var body: some View {
        Picker(title, selection: $day) {
            ForEach(1...31, id: \.self) { d in
                Text(d == 31 ? "End of month" : "\(d)").tag(d)
            }
        }
    }
}

/// Number pad used by the add-entry screen.
struct KeypadView: View {
    @Binding var amount: Int
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "000", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                Button {
                    press(key)
                } label: {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "delete.left")
                        } else {
                            Text(key)
                        }
                    }
                    .font(.title2.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.key))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            amount /= 10
        case "000":
            if amount > 0 && amount < 1_000_000 { amount *= 1000 }
        default:
            if let digit = Int(key), amount < 100_000_000 { amount = amount * 10 + digit }
        }
    }
}

/// One line in a transaction list.
struct EntryRow: View {
    let entry: Entry
    let lookup: Lookup
    var partnerName: String = SettingsKey.defaultPartnerName

    private var category: BudgetCategory? { lookup.category(entry.categoryID) }

    private var icon: String {
        switch entry.kind {
        case .expense, .income: return category?.emoji ?? "❔"
        case .transfer: return "🔄"
        case .payoff: return "💳"
        case .settlement: return "💞"
        case .adjust: return "⚖️"
        }
    }

    private var title: String {
        switch entry.kind {
        case .expense:
            let name = category?.name ?? "Uncategorised"
            return entry.merchant.isEmpty ? name : "\(entry.merchant) · \(name)"
        case .income: return category?.name ?? "Income"
        case .transfer: return "Transfer"
        case .payoff: return "Card payoff"
        case .settlement: return "\(partnerName) repaid"
        case .adjust: return "Balance adjustment"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        switch entry.kind {
        case .transfer, .payoff:
            parts.append("\(lookup.accountName(entry.accountID)) → \(lookup.accountName(entry.toAccountID))")
        default:
            parts.append(lookup.accountName(entry.accountID))
        }
        if !entry.note.isEmpty { parts.append(entry.note) }
        return parts.joined(separator: " · ")
    }

    private var amountText: String {
        switch entry.kind {
        case .expense: return entry.isRefund ? Yen.format(entry.amount, showPlus: true) : Yen.format(-entry.amount)
        case .income, .settlement: return Yen.format(entry.amount, showPlus: true)
        case .adjust: return Yen.format(entry.amount, showPlus: true)
        case .transfer, .payoff: return Yen.format(entry.amount)
        }
    }

    private var amountColor: Color {
        switch entry.kind {
        case .income, .settlement: return .green
        case .expense: return entry.isRefund ? .green : .primary
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(icon).font(.title3).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).lineLimit(1)
                    if entry.isSharedExpense {
                        Image(systemName: "person.2.fill").font(.caption2).foregroundStyle(.pink)
                    }
                    if entry.kind == .payoff && !entry.isConfirmed {
                        Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(.orange)
                    }
                    if entry.needsReview {
                        Image(systemName: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText).monospacedDigit().foregroundStyle(amountColor)
                if entry.isSharedExpense {
                    Text("mine \(Yen.format(entry.myShare))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Opens the right editor for an entry.
struct EntryEditorRouter: View {
    let entry: Entry

    var body: some View {
        switch entry.kind {
        case .expense, .income, .transfer:
            EntryEditorView(mode: .edit(entry))
        case .payoff, .settlement, .adjust:
            EntryDetailForm(entry: entry)
        }
    }
}
