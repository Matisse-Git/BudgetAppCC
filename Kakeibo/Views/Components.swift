import SwiftUI
import UIKit

/// The app's vocabulary of vibrations. Generators are kept alive and re-prepared after each use,
/// so the Taptic Engine is warm and fires without delay. iOS's System Haptics switch turns them all off.
/// Every tap is a full-strength impact: the soft, low-intensity ones were too faint to feel.
@MainActor
enum Haptics {
    private static let keyGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let bumpGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let liftGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let selectionGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Warm up everything, e.g. when the add screen appears.
    static func prepare() {
        keyGenerator.prepare()
        bumpGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// A number-pad key: a firm, clean tap.
    static func key() {
        keyGenerator.impactOccurred(intensity: 1.0)
        keyGenerator.prepare()
    }

    /// A key that did nothing (backspace on ¥0, digit limit reached): a heavier thud.
    static func blocked() {
        bumpGenerator.impactOccurred(intensity: 1.0)
        bumpGenerator.prepare()
    }

    /// A choice changed: a tab-like picker, a menu option, a toggle, a month.
    static func selection() {
        selectionGenerator.impactOccurred(intensity: 1.0)
        selectionGenerator.prepare()
    }

    /// Picking up or dropping a row while reordering.
    static func lift() {
        liftGenerator.impactOccurred(intensity: 1.0)
        liftGenerator.prepare()
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    /// Saved, but worth noticing (over budget, near a card limit) or destructive (delete).
    static func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }
}

extension SensoryFeedback {
    /// What `.sensoryFeedback` uses for a changed choice: a full-strength rigid tap instead of the faint
    /// system selection tick, matching `Haptics.selection()`.
    static let firmSelection = SensoryFeedback.impact(flexibility: .rigid, intensity: 1.0)
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

/// Whole-yen number field.
struct AmountField: View {
    let title: String
    @Binding var value: Int
    var allowNegative = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            YenField(placeholder: "¥0", value: $value, allowNegative: allowNegative)
                .frame(maxWidth: 160)
        }
    }
}

/// A yen amount typed on the number pad. The value updates on every keystroke: a
/// `TextField(value:format:)` only commits on Return, which the number pad doesn't have, so whatever was
/// typed was lost when you tapped Save.
struct YenField: View {
    let placeholder: String
    @Binding var value: Int
    var allowNegative = false
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(allowNegative ? .numbersAndPunctuation : .numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .onAppear { text = YenField.display(value) }
            .onChange(of: text) { _, typed in
                let parsed = YenField.parse(typed, allowNegative: allowNegative)
                if parsed != value { value = parsed }
                let shown = YenField.display(parsed)
                // Keep a lone "-" while a negative number is being typed.
                if shown != typed && !(allowNegative && typed == "-") { text = shown }
            }
            .onChange(of: value) { _, newValue in
                if YenField.parse(text, allowNegative: allowNegative) != newValue { text = YenField.display(newValue) }
            }
    }

    /// "12,000" for 12000, "−500" for -500, empty for 0 so the placeholder shows.
    nonisolated static func display(_ value: Int) -> String {
        guard value != 0 else { return "" }
        return value < 0 ? "-" + Yen.digits(value) : Yen.digits(value)
    }

    /// Digits typed so far (full-width too), capped at ten digits.
    nonisolated static func parse(_ text: String, allowNegative: Bool) -> Int {
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let digits = String(halfWidth.filter { $0.isASCII && $0.isNumber }.prefix(10))
        let magnitude = Int(digits) ?? 0
        let negative = allowNegative && (halfWidth.contains("-") || halfWidth.contains("−"))
        return negative ? -magnitude : magnitude
    }
}

/// A percentage like 15.0, saved on every keystroke (see `YenField`). Empty means 0.
struct PercentField: View {
    let placeholder: String
    @Binding var value: Double
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .onAppear { text = PercentField.display(value) }
            .onChange(of: text) { _, typed in
                let parsed = PercentField.parse(typed)
                if parsed != value { value = parsed }
            }
    }

    nonisolated static func display(_ value: Double) -> String {
        guard value > 0 else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "15", "14.6", "14,6" (decimal comma) → a number between 0 and 100.
    nonisolated static func parse(_ text: String) -> Double {
        let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let cleaned = halfWidth.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        return min(max(Double(cleaned) ?? 0, 0), 100)
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
