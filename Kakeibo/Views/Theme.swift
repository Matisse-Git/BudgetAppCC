import SwiftUI
import UIKit

// Shared look: Apple system colours, quiet cards, and line icons instead of emoji.
// Colour carries meaning only: a few categories get their own hue, red means over budget
// or short of money, orange means a bill is close.

extension Color {
    /// A colour with separate light and dark values.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let tileFill = Color(uiColor: .tertiarySystemGroupedBackground)
    static let barTrack = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)

    static let categoryBlue = Color(uiColor: .systemBlue)
    static let categoryAmber = Color.dynamic(light: 0xA86400, dark: 0xD99A1E)
    static let categoryPurple = Color(uiColor: .systemPurple)
    static let categoryTeal = Color.dynamic(light: 0x16819A, dark: 0x2FB3CF)
    static let categoryNeutral = Color(uiColor: .systemGray)
    static let shortfall = Color.dynamic(light: 0xD70015, dark: 0xFF6961)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Icon and tint for a category, matched on its name. Unknown categories keep their emoji.
struct CategoryLook {
    let symbol: String?
    let tint: Color
    /// True for categories that get their own colour in charts; the rest fold into "Everything else".
    var isHighlighted = false

    static func of(_ category: BudgetCategory?) -> CategoryLook {
        guard let category else { return CategoryLook(symbol: "questionmark", tint: .categoryNeutral) }
        switch category.name.lowercased() {
        case "rent": return CategoryLook(symbol: "house", tint: .categoryBlue, isHighlighted: true)
        case "supermarket", "groceries": return CategoryLook(symbol: "cart", tint: .categoryAmber, isHighlighted: true)
        case "shopping": return CategoryLook(symbol: "bag", tint: .categoryPurple, isHighlighted: true)
        case "restaurants", "eating out": return CategoryLook(symbol: "fork.knife", tint: .categoryTeal, isHighlighted: true)
        case "utilities": return CategoryLook(symbol: "bolt", tint: .categoryNeutral)
        case "phone": return CategoryLook(symbol: "iphone", tint: .categoryNeutral)
        case "transport": return CategoryLook(symbol: "tram", tint: .categoryNeutral)
        case "konbini": return CategoryLook(symbol: "storefront", tint: .categoryNeutral)
        case "subscriptions": return CategoryLook(symbol: "repeat", tint: .categoryNeutral)
        case "other": return CategoryLook(symbol: "shippingbox", tint: .categoryNeutral)
        case "salary": return CategoryLook(symbol: "yensign", tint: .green)
        default:
            if category.kind == .income {
                return CategoryLook(symbol: category.name.lowercased().hasPrefix("dad") ? "gift" : nil, tint: .green)
            }
            return CategoryLook(symbol: nil, tint: .categoryNeutral)
        }
    }
}

extension AccountKind {
    var symbol: String {
        switch self {
        case .bank: return "building.columns"
        case .topUp: return "wallet.pass"
        case .cash: return "banknote"
        case .credit: return "creditcard"
        }
    }
}

/// Rounded square (or circle) with a tinted icon.
struct IconTile: View {
    var symbol: String?
    var emoji: String = ""
    var tint: Color = .secondary
    var size: CGFloat = 40
    var circle = false
    var neutral = false

    var body: some View {
        ZStack {
            if circle {
                Circle().fill(neutral ? Color.tileFill : tint.opacity(0.18))
            } else {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(neutral ? Color.tileFill : tint.opacity(0.18))
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(neutral ? Color.secondary : tint)
            } else {
                Text(emoji).font(.system(size: size * 0.48))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Category icon tile, falling back to the category's emoji.
struct CategoryTile: View {
    let category: BudgetCategory?
    var size: CGFloat = 40
    var circle = false

    var body: some View {
        let look = CategoryLook.of(category)
        IconTile(symbol: look.symbol, emoji: category?.emoji ?? "", tint: look.tint, size: size, circle: circle,
                 neutral: !look.isHighlighted && category?.kind != .income)
    }
}

/// "Budgets ... See all" style header above a card.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Spacer()
            trailing.font(.body)
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Card that holds rows separated by inset hairlines.
struct RowsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.card))
    }
}

struct RowDivider: View {
    var inset: CGFloat = 52

    var body: some View {
        Rectangle().fill(Color.hairline).frame(height: 0.5).padding(.leading, inset)
    }
}

extension Yen {
    /// Short axis label: ¥200k, ¥1.2M.
    static func short(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            let millions = Double(value) / 1_000_000
            return "¥" + millions.formatted(.number.precision(.fractionLength(0...1))) + "M"
        }
        if absolute >= 1_000 {
            return "¥\(value / 1_000)k"
        }
        return "¥\(value)"
    }
}
