import SwiftUI
import UIKit

extension Color {
    // Legacy names for the old screens; new code uses `Palette` directly.
    static let groupedBackground = Palette.background
    static let card = Palette.card
    static let chip = Palette.chipFill
    static let key = Palette.controlFill
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

/// The app's vocabulary of vibrations. Generators are kept alive and re-prepared after each use,
/// so the Taptic Engine is warm and fires without delay. iOS's System Haptics switch turns them all off.
@MainActor
enum Haptics {
    private static let keyGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let bumpGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let liftGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Warm up everything, e.g. when the add screen appears.
    static func prepare() {
        keyGenerator.prepare()
        bumpGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// A number-pad key: a very light, soft tick.
    static func key() {
        keyGenerator.impactOccurred(intensity: 0.55)
        keyGenerator.prepare()
    }

    /// A key that did nothing (backspace on ¥0, digit limit reached).
    static func blocked() {
        bumpGenerator.impactOccurred(intensity: 0.6)
        bumpGenerator.prepare()
    }

    /// A choice changed: a tab-like picker, a menu option, a toggle, a month.
    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Picking up or dropping a row while reordering.
    static func lift() {
        liftGenerator.impactOccurred(intensity: 0.7)
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    /// Saved, but worth noticing (over budget) or destructive (delete).
    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }
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
    var tint: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.barTrack)
                Capsule()
                    .fill(isOver ? Color.red : tint)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
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

/// The Quick Add keypad (canvas Foundations): 58 pt keys, 00 and 000 for yen, Save in the thumb zone.
///
///     1   2   3   ⌫
///     4   5   6   ┐
///     7   8   9   Save
///     00  0   000 ┘
struct KeypadView: View {
    @Binding var amount: Int
    var canSave: Bool
    var saveTitle: String = "Save"
    var onSave: () -> Void
    @AppStorage(SettingsKey.keypadHaptics) private var haptics = true

    private let spacing = Metrics.keySpacing

    var body: some View {
        HStack(spacing: spacing) {
            column(["1", "4", "7", "00"])
            column(["2", "5", "8", "0"])
            column(["3", "6", "9", "000"])
            VStack(spacing: spacing) {
                key("⌫")
                saveKey
                    .frame(height: Metrics.keyHeight * 3 + spacing * 2)
            }
        }
    }

    private func column(_ keys: [String]) -> some View {
        VStack(spacing: spacing) {
            ForEach(keys, id: \.self) { key($0) }
        }
    }

    private func key(_ key: String) -> some View {
        Button {
            press(key)
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 24, weight: .regular))
                } else {
                    Text(key)
                        .font(.system(size: key.count > 1 ? 24 : 26, weight: .medium))
                }
            }
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.keyHeight)
            .background(RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous).fill(Palette.controlFill))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous))
        }
        .buttonStyle(KeyButtonStyle())
        .accessibilityLabel(key == "⌫" ? "Delete" : key)
    }

    private var saveKey: some View {
        Button {
            onSave()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                Text(saveTitle)
                    .font(.headline)
            }
            .foregroundStyle(Color.white.opacity(canSave ? 1 : 0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous)
                    .fill(Palette.accentFill.opacity(canSave ? 1 : 0.32))
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous))
        }
        .buttonStyle(KeyButtonStyle())
        .disabled(!canSave)
        .accessibilityLabel(saveTitle)
    }

    private func press(_ key: String) {
        let next = KeypadView.apply(key, to: amount)
        if haptics {
            if next == amount { Haptics.blocked() } else { Haptics.key() }
        }
        amount = next
    }

    /// The amount after pressing `key`. Returns the same amount when the key does nothing.
    /// Amounts stop at nine digits.
    nonisolated static func apply(_ key: String, to amount: Int) -> Int {
        switch key {
        case "⌫":
            return amount / 10
        case "00":
            return amount > 0 && amount < 10_000_000 ? amount * 100 : amount
        case "000":
            return amount > 0 && amount < 1_000_000 ? amount * 1000 : amount
        default:
            if let digit = Int(key), amount < 100_000_000 { return amount * 10 + digit }
            return amount
        }
    }
}

/// Keys dim a little while pressed.
struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// One line in a transaction list.
struct EntryRow: View {
    let entry: Entry
    let lookup: Lookup
    var partnerName: String = SettingsKey.defaultPartnerName

    private var category: BudgetCategory? { lookup.category(entry.categoryID) }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .expense, .income: CategoryTile(category: category, size: 40, circle: true)
        case .transfer: IconTile(symbol: "arrow.left.arrow.right", size: 40, circle: true, neutral: true)
        case .payoff: IconTile(symbol: "creditcard", size: 40, circle: true, neutral: true)
        case .settlement: IconTile(symbol: "heart", tint: .pink, size: 40, circle: true)
        case .adjust: IconTile(symbol: "slider.horizontal.3", size: 40, circle: true, neutral: true)
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
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title).font(.body).lineLimit(1)
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
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText).monospacedDigit().foregroundStyle(amountColor)
                if entry.isSharedExpense {
                    Text("mine \(Yen.format(entry.myShare))").font(.footnote).foregroundStyle(.secondary)
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
