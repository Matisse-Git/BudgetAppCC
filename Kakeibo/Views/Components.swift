import SwiftUI
import UIKit

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
