import SwiftUI
import UIKit

// Design tokens from the Kakeibo canvas (Foundations artboard). Compiled into the app and the widget.
// Dark values are the canvas's own. The canvas is dark-only, so light values are derived: the iOS
// light equivalents, darkened where needed so every text colour keeps 4.5:1 on its surface.
// The full table lives in CLAUDE.md; keep the two in step.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: CGFloat(alpha)))
    }

    /// A colour with separate light and dark values.
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: CGFloat(darkAlpha))
                : UIColor(hex: light, alpha: CGFloat(lightAlpha))
        })
    }
}

/// Surfaces, text, the indigo accent and the colours that carry meaning.
enum Palette {
    // MARK: Surfaces
    /// Screen background.
    static let background = Color.dynamic(light: 0xF2F2F7, dark: 0x000000)
    /// Cards on a screen.
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Sheet background.
    static let sheet = Color.dynamic(light: 0xF2F2F7, dark: 0x1C1C1E)
    /// Grouped rows inside a sheet.
    static let sheetRow = Color.dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    /// Keypad keys, secondary buttons, segmented-control track (#767680 at 24%).
    static let controlFill = Color.dynamic(light: 0x767680, dark: 0x767680, lightAlpha: 0.12, darkAlpha: 0.24)
    /// Chips and pickers in the add sheet (#767680 at 20%).
    static let chipFill = Color.dynamic(light: 0x767680, dark: 0x767680, lightAlpha: 0.12, darkAlpha: 0.20)
    /// Empty part of a progress bar (#767680 at 30%).
    static let track = Color.dynamic(light: 0x767680, dark: 0x767680, lightAlpha: 0.16, darkAlpha: 0.30)
    /// Row dividers inside cards.
    static let separator = Color.dynamic(light: 0x3C3C43, dark: 0x545458, lightAlpha: 0.22, darkAlpha: 0.42)
    /// Selected segment of a segmented control.
    static let segmentSelected = Color.dynamic(light: 0xFFFFFF, dark: 0x636366)
    /// Selected tab behind its icon in the tab bar.
    static let tabSelection = Color.dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.11)
    /// Undo toast.
    static let toast = Color.dynamic(light: 0xFFFFFF, dark: 0x3A3A3E, lightAlpha: 0.98, darkAlpha: 0.97)

    // MARK: Text
    static let textPrimary = Color.dynamic(light: 0x000000, dark: 0xFFFFFF)
    static let textSecondary = Color.dynamic(light: 0x6E6E73, dark: 0x98989F)
    /// Chevrons and other quiet glyphs.
    static let textTertiary = Color.dynamic(light: 0xAEAEB2, dark: 0x6E6E73)

    // MARK: Accent · Ai indigo (藍)
    /// The one prominent action per surface; white text on it.
    static let accentFill = Color(hex: 0x5E5CE6)
    /// Links and icons.
    static let accentTint = Color.dynamic(light: 0x5856D6, dark: 0x8A87FF)
    /// Charts and the overall budget bar.
    static let accentData = Color.dynamic(light: 0x5E5CE6, dark: 0x7D7AFF)
    /// Soft indigo fill behind "Auto", "Undo", "Back Up Now".
    static let accentSoftFill = Color.dynamic(light: 0x5856D6, dark: 0x8A87FF, lightAlpha: 0.14, darkAlpha: 0.20)
    /// Text on `accentSoftFill`.
    static let accentSoftText = Color.dynamic(light: 0x4B49C4, dark: 0xA9A7FF)

    // MARK: Meaning
    /// Income, on track, covered.
    static let positive = Color.dynamic(light: 0x1F7A35, dark: 0x30D158)
    /// Over budget and delete, as a fill.
    static let negative = Color.dynamic(light: 0xFF3B30, dark: 0xFF453A)
    /// Over budget and delete, as text.
    static let negativeText = Color.dynamic(light: 0xD70015, dark: 0xFF6961)
    /// Shortfall, at risk, spent more.
    static let warning = Color.dynamic(light: 0xC93400, dark: 0xFF9F0A)
    /// Spent less (blue against orange).
    static let info = Color.dynamic(light: 0x0A64D6, dark: 0x409CFF)
    /// Today's pace tick on budget bars.
    static let paceTick = Color.dynamic(light: 0x000000, dark: 0xFFFFFF)
}

/// Category and account hues. Squares are categories, circles are accounts.
enum Hue: String, CaseIterable {
    case green, orange, tan, blue, purple, pink, mint, yellow, cyan, gray, teal, indigo

    var color: Color {
        switch self {
        case .green: return .dynamic(light: 0x1F9E45, dark: 0x30D158)
        case .orange: return .dynamic(light: 0xE07B00, dark: 0xFF9F0A)
        case .tan: return .dynamic(light: 0x9C7651, dark: 0xC9A27E)
        case .blue: return .dynamic(light: 0x1F7AE0, dark: 0x409CFF)
        case .purple: return .dynamic(light: 0xA44BD6, dark: 0xBF5AF2)
        case .pink: return .dynamic(light: 0xE0244D, dark: 0xFF375F)
        case .mint: return .dynamic(light: 0x16A39F, dark: 0x63E6E2)
        case .yellow: return .dynamic(light: 0xC29A00, dark: 0xFFD60A)
        case .cyan: return .dynamic(light: 0x1A9BCF, dark: 0x64D2FF)
        case .gray: return .dynamic(light: 0x8E8E93, dark: 0xAEAEB2)
        case .teal: return .dynamic(light: 0x1C9AB0, dark: 0x40C8E0)
        case .indigo: return .dynamic(light: 0x5E5CE6, dark: 0x7D7AFF)
        }
    }

    /// Opacity of the tile behind the glyph (the canvas uses 16–20% depending on the hue).
    var fillOpacity: Double {
        switch self {
        case .tan, .purple: return 0.20
        case .mint, .yellow, .cyan: return 0.16
        default: return 0.18
        }
    }

    var fill: Color { color.opacity(fillOpacity) }

    /// Hues handed out to categories and accounts that have no fixed look.
    static let rotation: [Hue] = [.green, .orange, .tan, .blue, .purple, .pink, .mint, .yellow, .cyan, .teal]
}

/// The colours a credit card can be (CardSetup artboard). Same in light and dark: white text sits on them.
enum CardColor: String, CaseIterable, Identifiable {
    case blue, teal, raspberry, amber, violet, graphite

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: return Color(hex: 0x3D52D5)
        case .teal: return Color(hex: 0x0F7B6C)
        case .raspberry: return Color(hex: 0xB8325A)
        case .amber: return Color(hex: 0xB9651B)
        case .violet: return Color(hex: 0x6B4FBB)
        case .graphite: return Color(hex: 0x48484A)
        }
    }

    /// Brighter version for bars and glyphs drawn on the dark card background (e.g. the bill building up).
    var bright: Color {
        switch self {
        case .blue: return Color(hex: 0x8291F0)
        case .teal: return Color(hex: 0x5FD3C1)
        case .raspberry: return Color(hex: 0xE0577E)
        case .amber: return Color(hex: 0xE8944A)
        case .violet: return Color(hex: 0x9E86E8)
        case .graphite: return Color(hex: 0xA1A1A6)
        }
    }

    /// A stable default for a card that hasn't picked a colour.
    static func fallback(for key: String) -> CardColor {
        allCases[StableHash.of(key) % allCases.count]
    }
}

/// Spacing, radii and sizes.
enum Metrics {
    /// Side gutter of every screen.
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 24
    /// Grouped rows inside a sheet.
    static let sheetGroupRadius: CGFloat = 22
    static let cardPadding: CGFloat = 16
    /// Gap between a section and the next title.
    static let sectionSpacing: CGFloat = 28
    static let rowHeight: CGFloat = 62
    static let compactRowHeight: CGFloat = 50
    /// Category square / account circle in list rows.
    static let rowIcon: CGFloat = 32
    static let buttonHeight: CGFloat = 44
    static let keyHeight: CGFloat = 58
    static let keyRadius: CGFloat = 16
    static let keySpacing: CGFloat = 8
}

/// SF Pro with Dynamic Type for text; fixed sizes for the big yen figures, which shrink to fit instead.
/// Amounts always use tabular figures (`.monospacedDigit()`); yen never shows decimals.
extension Font {
    /// Amount being typed on the keypad · 64 Bold, tracking −2.
    static let kAmountEntry = Font.system(size: 64, weight: .bold)
    /// The ¥ in front of it · 34 Semibold, secondary.
    static let kAmountCurrency = Font.system(size: 34, weight: .semibold)
    /// Hero amount (budget left, transaction) · 44 Bold, tracking −1.2.
    static let kHero = Font.system(size: 44, weight: .bold)
    /// Balance on an account or category page · 40 Bold, tracking −1.
    static let kDetailAmount = Font.system(size: 40, weight: .bold)
    /// Card statistic (net worth, statement) · 34 Bold, tracking −0.8.
    static let kStat = Font.system(size: 34, weight: .bold)
    /// Section heading in caps · 13 Semibold, tracking 0.2.
    static let kSectionCaps = Font.footnote.weight(.semibold)
    /// Tab bar label · 10 Semibold.
    static let kTabLabel = Font.system(size: 10, weight: .semibold)
}

/// djb2 over UTF-8. Swift's `hashValue` changes every launch, so it can't pick a lasting colour.
enum StableHash {
    static func of(_ text: String) -> Int {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Int(hash % 1_000_003)
    }
}
