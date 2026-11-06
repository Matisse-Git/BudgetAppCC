import SwiftUI

// Category and account looks from the Foundations artboard: squares are categories, circles are
// accounts, card shapes are credit cards. Glyphs are SF Symbols; colours come from `Hue` and `CardColor`
// in Shared/DesignTokens.swift.

/// Icon and hue for a category, matched on its name (with common synonyms). Categories that match
/// nothing keep their emoji and get a hue picked from their name, so it never changes between launches.
struct CategoryLook {
    let symbol: String?
    let hue: Hue

    var tint: Color { hue.color }
    var fill: Color { hue.fill }

    private static let table: [(names: [String], symbol: String, hue: Hue)] = [
        (["groceries", "grocery", "supermarket"], "cart.fill", .green),
        (["dining out", "dining", "restaurants", "restaurant", "eating out"], "fork.knife", .orange),
        (["café & snacks", "cafe & snacks", "café", "cafe", "coffee", "snacks", "konbini"], "cup.and.saucer.fill", .tan),
        (["transport", "transit", "train", "travel"], "tram.fill", .blue),
        (["shopping", "clothes"], "bag.fill", .purple),
        (["entertainment", "fun", "leisure", "hobbies"], "ticket.fill", .pink),
        (["health & beauty", "health", "beauty", "medical", "pharmacy"], "heart.fill", .mint),
        (["utilities", "electricity", "gas", "water"], "bolt.fill", .yellow),
        (["phone & internet", "phone", "internet", "mobile"], "wifi", .cyan),
        (["subscriptions", "subscription"], "repeat", .gray),
        (["rent", "housing", "home"], "house.fill", .indigo),
        (["other", "misc", "miscellaneous", "everything else"], "square.grid.2x2.fill", .gray),
        // Income
        (["salary", "wages", "pay"], "yensign", .green),
        (["bonus"], "star.fill", .yellow),
        (["side income", "freelance"], "briefcase.fill", .cyan),
        (["refund", "refunds"], "arrow.uturn.backward", .gray),
        (["gift", "gifts"], "gift.fill", .pink),
    ]

    static func of(_ category: BudgetCategory?) -> CategoryLook {
        guard let category else { return CategoryLook(symbol: "questionmark", hue: .gray) }
        let name = category.name.lowercased().trimmingCharacters(in: .whitespaces)
        if let match = table.first(where: { $0.names.contains(name) }) {
            return CategoryLook(symbol: match.symbol, hue: match.hue)
        }
        if name.hasPrefix("dad") || name.contains("gift") {
            return CategoryLook(symbol: "gift.fill", hue: .pink)
        }
        return CategoryLook(symbol: nil, hue: Hue.rotation[StableHash.of(name) % Hue.rotation.count])
    }
}

/// Icon and hue for an account. Credit cards are drawn as a small card in their own colour instead.
struct AccountLook {
    let symbol: String
    let hue: Hue

    static func of(_ account: Account) -> AccountLook {
        let base = defaultLook(account)
        if let chosen = Hue(rawValue: account.colorKey) {
            return AccountLook(symbol: base.symbol, hue: chosen)
        }
        return base
    }

    private static func defaultLook(_ account: Account) -> AccountLook {
        switch account.kind {
        case .bank:
            return AccountLook(symbol: "building.columns.fill", hue: .blue)
        case .cash:
            return AccountLook(symbol: "banknote.fill", hue: .tan)
        case .credit:
            return AccountLook(symbol: "creditcard.fill", hue: .indigo)
        case .topUp:
            let name = account.name.lowercased()
            let transit = ["pasmo", "suica", "icoca", "manaca", "toica", "kitaca", "nimoca", "transit", " ic"]
            if transit.contains(where: { name.contains($0) }) || name == "ic" {
                return AccountLook(symbol: "wave.3.right", hue: .green)
            }
            let qr = ["paypay", "qr", "merpay", "rakuten pay", "au pay", "d払い", "line pay"]
            if qr.contains(where: { name.contains($0) }) {
                return AccountLook(symbol: "qrcode", hue: .pink)
            }
            return AccountLook(symbol: "wallet.pass.fill", hue: .cyan)
        }
    }

    /// Colour of a credit card's face.
    static func cardColor(_ account: Account) -> CardColor {
        CardColor(rawValue: account.colorKey) ?? CardColor.fallback(for: account.id.uuidString)
    }
}

extension AccountKind {
    var symbol: String {
        switch self {
        case .bank: return "building.columns.fill"
        case .topUp: return "wallet.pass.fill"
        case .cash: return "banknote.fill"
        case .credit: return "creditcard.fill"
        }
    }
}

// MARK: - Legacy helpers
// Kept only until every screen is rebuilt on the new components (DesignComponents.swift), then deleted.

extension Color {
    static let tileFill = Palette.controlFill
    static let barTrack = Palette.track
    static let hairline = Palette.separator
    static let categoryNeutral = Hue.gray.color
    static let shortfall = Palette.negativeText
}

/// Rounded square (or circle) with a tinted icon.
struct IconTile: View {
    var symbol: String?
    var emoji: String = ""
    var tint: Color = Palette.textSecondary
    var size: CGFloat = 40
    var circle = false
    var neutral = false

    var body: some View {
        ZStack {
            if circle {
                Circle().fill(neutral ? Palette.controlFill : tint.opacity(0.18))
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(neutral ? Palette.controlFill : tint.opacity(0.18))
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(neutral ? Palette.textSecondary : tint)
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
        IconTile(symbol: look.symbol, emoji: category?.emoji ?? "", tint: look.tint, size: size, circle: circle)
    }
}

/// "Budgets ... See all" style header above a card.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            trailing.font(.subheadline)
        }
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
        .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).fill(Palette.card))
    }
}

struct RowDivider: View {
    var inset: CGFloat = 52

    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 0.5).padding(.leading, inset)
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
