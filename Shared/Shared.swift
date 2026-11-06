import Foundation
import AppIntents

// Code compiled into both the app and the widget extension.

/// The App Group shared by the app and its widget.
///
/// AltStore / SideStore rewrite App Group identifiers when they re-sign the app
/// and record the real ones under `ALTAppGroups` in Info.plist, so read that first.
enum AppGroup {
    static let fallbackIdentifier = "group.com.matisse.kakeibo"

    static var identifier: String {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let first = groups.first {
            return first
        }
        return fallbackIdentifier
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// Yen formatting and parsing. Amounts are whole yen stored as `Int`.
enum Yen {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f
    }()

    /// "11,300": the number without the yen sign, for the keypad display.
    static func digits(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
    }

    static func format(_ value: Int, showPlus: Bool = false) -> String {
        let body = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value))"
        if value < 0 { return "−¥" + body }
        if showPlus && value > 0 { return "+¥" + body }
        return "¥" + body
    }

    /// Parses amounts like "¥1,234", "￥１，２３４", "1234.00", "JPY 980", "1.234,00".
    static func parse(_ raw: String) -> Int? {
        var text = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop a trailing decimal part (yen has no minor unit).
        if let range = text.range(of: #"[.,]\d{1,2}$"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        let negative = text.contains("-") || text.contains("−")
        let digits = text.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        return negative ? -value : value
    }
}

/// The next unpaid card bill, for the widget.
struct NextBillSnapshot: Codable {
    var cardName: String
    /// `CardColor` raw value.
    var colorKey: String
    var amount: Int
    var dueDate: Date
    var payerName: String?
    var shortfall: Int
}

/// Small summary the app writes for the widget. Fields added later are optional so an older snapshot
/// still decodes.
struct WidgetSnapshot: Codable {
    var monthTitle: String
    var spent: Int
    var budget: Int
    var partnerOwed: Int
    var updatedAt: Date
    var daysElapsed: Int? = nil
    var daysInMonth: Int? = nil
    var perDay: Int? = nil
    /// "onTrack", "atRisk" or "over".
    var paceStatus: String? = nil
    /// The category that most needs a look, e.g. "Dining Out ¥1,800 over".
    var alert: String? = nil
    var nextBill: NextBillSnapshot? = nil

    static let key = "widgetSnapshot"

    static let placeholder = WidgetSnapshot(
        monthTitle: "November", spent: 74_820, budget: 130_000, partnerOwed: 0, updatedAt: Date(),
        daysElapsed: 18, daysInMonth: 30, perDay: 4_600, paceStatus: "onTrack", alert: "Dining Out ¥1,800 over",
        nextBill: NextBillSnapshot(cardName: "Everyday Card", colorKey: "blue", amount: 86_420,
                                   dueDate: Date().addingTimeInterval(9 * 86_400), payerName: "Main Bank", shortfall: 0)
    )

    var left: Int { budget - spent }
    var fraction: Double { budget > 0 ? Double(spent) / Double(budget) : 0 }
    var paceFraction: Double? {
        guard let daysElapsed, let daysInMonth, daysInMonth > 0 else { return nil }
        return Double(daysElapsed) / Double(daysInMonth)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            AppGroup.defaults.set(data, forKey: Self.key)
        }
    }
}

/// Lets intents and controls ask the app to open the add-entry screen.
enum PendingAction {
    static let addKey = "pendingAddEntry"
    static let notification = Notification.Name("KakeiboOpenAddEntry")

    static func requestAdd() {
        UserDefaults.standard.set(true, forKey: addKey)
        AppGroup.defaults.set(true, forKey: addKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func consumeAdd() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: addKey) || AppGroup.defaults.bool(forKey: addKey)
        UserDefaults.standard.set(false, forKey: addKey)
        AppGroup.defaults.set(false, forKey: addKey)
        return pending
    }
}

/// Opens Kakeibo on the add-entry screen. Used by the Control Center button,
/// the Action Button and Shortcuts.
struct OpenAddEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Kakeibo Entry"
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAction.requestAdd()
        return .result()
    }
}
