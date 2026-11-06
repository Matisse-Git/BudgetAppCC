import SwiftUI

// Building blocks from the canvas. Measurements follow the artboards: 24 pt cards, 62 pt rows with a
// 32 pt icon, 12 pt gaps, hairlines inset to the text, 44 pt pill buttons. Colours come from `Palette`.

// MARK: - Surfaces

extension View {
    /// A card on a screen: card colour, 24 pt continuous corners.
    func kCard(padding: CGFloat = Metrics.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
    }

    /// The screen background behind scrolling content.
    func kScreenBackground() -> some View {
        self.background(Palette.background.ignoresSafeArea())
    }
}

/// A card holding rows. Rows bring their own padding; put a `ListDivider` between them.
struct CardList<Content: View>: View {
    var background: Color = Palette.card
    var radius: CGFloat = Metrics.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Hairline between rows, inset to where the text starts (16 + 32 icon + 12 = 60 by default).
struct ListDivider: View {
    var inset: CGFloat = 60

    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

/// Glass in iOS 26, a material before it.
struct GlassBackground<S: Shape>: ViewModifier {
    var shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }
}

// MARK: - Rows

/// The standard list row: icon, title over a footnote, and something on the right.
struct KRow<Leading: View, Subtitle: View, Trailing: View>: View {
    let title: String
    var titleWeight: Font.Weight = .medium
    var minHeight: CGFloat = Metrics.rowHeight
    var chevron = false
    let leading: Leading
    let subtitle: Subtitle
    let trailing: Trailing

    init(
        _ title: String,
        titleWeight: Font.Weight = .medium,
        minHeight: CGFloat = Metrics.rowHeight,
        chevron: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.titleWeight = titleWeight
        self.minHeight = minHeight
        self.chevron = chevron
        self.leading = leading()
        self.subtitle = subtitle()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.body.weight(titleWeight))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                subtitle
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            if chevron { Chevron() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
    }
}

extension KRow where Subtitle == Text? {
    init(
        _ title: String,
        subtitle: String?,
        titleWeight: Font.Weight = .medium,
        minHeight: CGFloat = Metrics.rowHeight,
        chevron: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title, titleWeight: titleWeight, minHeight: minHeight, chevron: chevron,
                  leading: leading, subtitle: { subtitle.map { Text($0) } }, trailing: trailing)
    }
}

/// Amount on the right of a row, with an optional caption under it (a time, a due date, a status).
struct AmountStack<Caption: View>: View {
    let amount: String
    var color: Color = Palette.textPrimary
    let caption: Caption

    init(_ amount: String, color: Color = Palette.textPrimary, @ViewBuilder caption: () -> Caption) {
        self.amount = amount
        self.color = color
        self.caption = caption()
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(amount)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
            caption
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

extension AmountStack where Caption == Text? {
    init(_ amount: String, color: Color = Palette.textPrimary, caption: String? = nil) {
        self.init(amount, color: color) { caption.map { Text($0) } }
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.textTertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Icons

/// A category's rounded square. Selected tiles are filled with the hue and the glyph turns black.
struct CategoryIcon: View {
    let category: BudgetCategory?
    var size: CGFloat = Metrics.rowIcon
    var selected = false

    var body: some View {
        let look = CategoryLook.of(category)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(selected ? look.tint : look.fill)
            if let symbol = look.symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundStyle(selected ? Color.black : look.tint)
            } else {
                Text(category?.emoji ?? "")
                    .font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A glyph on a tinted square or circle, for things that aren't categories (transfers, adjustments).
struct SymbolTile: View {
    let symbol: String
    var hue: Hue = .gray
    var size: CGFloat = Metrics.rowIcon
    var circle = false

    var body: some View {
        ZStack {
            if circle {
                Circle().fill(hue.fill)
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(hue.fill)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(hue.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A credit card in miniature (36 × 24 in rows), in the card's own colour.
struct MiniCard: View {
    let color: Color
    var width: CGFloat = 36

    var body: some View {
        let height = width * 2 / 3
        let radius = width * 0.14
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: width * 0.055, style: .continuous)
                    .fill(Color.white.opacity(0.6))
                    .frame(width: width * 0.22, height: width * 0.167)
                    .offset(x: width * 0.14, y: height * 0.29)
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// An account's circle, or a mini card for credit cards.
struct AccountIcon: View {
    let account: Account?
    var size: CGFloat = Metrics.rowIcon

    var body: some View {
        if let account, account.kind == .credit {
            MiniCard(color: AccountLook.cardColor(account).color, width: size * 1.125)
                .frame(width: size * 1.125, height: size)
        } else if let account {
            let look = AccountLook.of(account)
            SymbolTile(symbol: look.symbol, hue: look.hue, size: size, circle: true)
        } else {
            SymbolTile(symbol: "questionmark", size: size, circle: true)
        }
    }
}

// MARK: - Headings

/// Title 3 heading above a card, with an optional link on the right ("Needs attention … Budgets").
struct SectionTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing.font(.subheadline)
        }
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// Small caps heading above a grouped card ("BANK ACCOUNTS … ¥1,416,130").
struct SectionCaps: View {
    let title: String
    var trailing: String? = nil
    var inset: CGFloat = 16

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).monospacedDigit()
            }
        }
        .font(.kSectionCaps)
        .kerning(0.2)
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, inset)
    }
}

// MARK: - Budget bar

/// Progress against a budget, with a tick at today's pace (budget × day ÷ days in month).
/// The fill turns red past 100%.
struct BudgetBar: View {
    /// Spent ÷ budget. Above 1 means over.
    let fraction: Double
    /// Today's pace as a fraction of the budget, nil for no tick.
    var pace: Double? = nil
    var tint: Color = Palette.accentData
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filled = width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Palette.track)
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(fraction > 1 ? Palette.negative : tint)
                    .frame(width: filled)
                if let pace {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.paceTick)
                        .frame(width: 2, height: height + 6)
                        .offset(x: width * min(max(pace, 0), 1) - 1)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Chips and buttons

/// "On track", "¥11,300 short": a tinted capsule with an optional dot.
struct StatusChip: View {
    let text: String
    let tint: Color
    var dot = false

    var body: some View {
        HStack(spacing: 6) {
            if dot {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(tint)
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.15)))
    }
}

/// Marks a card payoff Kakeibo recorded by itself.
struct AutoBadge: View {
    var body: some View {
        Text("Auto")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.accentSoftText)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.accentSoftFill))
    }
}

/// 44 pt capsule. Prominent is the one indigo action on a surface; the other is a grey fill.
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var fill = true
    var height: CGFloat = Metrics.buttonHeight

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        PillLabel(configuration: configuration, prominent: prominent, fill: fill, height: height)
    }

    private struct PillLabel: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let fill: Bool
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Color.white : Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .frame(maxWidth: fill ? .infinity : nil, minHeight: height)
                .background(Capsule().fill(prominent ? Palette.accentFill : Palette.controlFill))
                .contentShape(Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(prominent: false) }
}

// MARK: - Toast

/// "Saved ¥980 · Dining Out · Wallet  [Undo]". Shown instead of a dialog after saving.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Palette.background)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Palette.positive))
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accentSoftText)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Capsule().fill(Palette.accentSoftFill))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background(
            Capsule()
                .fill(Palette.toast)
                .shadow(color: .black.opacity(0.35), radius: 16, y: 12)
        )
    }
}
