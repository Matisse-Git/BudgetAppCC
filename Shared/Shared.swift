import Foundation
import AppIntents

// Code compiled into both the app and the widget extension.

/// The App Group shared by the app and its widget.
///
/// Sideloaders sign with a free Apple ID, which can't use our own group name, so they register a
/// group of their own and sign both the app and the widget with it:
/// - AltStore / SideStore record it under `ALTAppGroups` in each Info.plist.
/// - iLoader (isideload) registers `group.<bundle id>.<team id>` and writes no Info.plist key; the group
///   is only in the provisioning profile it embeds in each bundle (`embedded.mobileprovision`).
/// Asking iOS for a group the app isn't signed with quietly gives a private, unshared store, so the
/// widget would only ever see placeholders. Without either source (simulator, Xcode) our own name is used.
enum AppGroup {
    static let fallbackIdentifier = "group.com.matisse.kakeibo"

    /// Worked out once per process.
    static let identifier: String = resolve(
        altGroups: Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
        profileGroups: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
            .map(groups(inProvisioningProfile:)) ?? []
    )

    static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    /// `ALTAppGroups` first, then the profile's groups (ours by name if there are several), then our own name.
    static func resolve(altGroups: [String]?, profileGroups: [String]) -> String {
        if let first = altGroups?.first(where: { !$0.isEmpty }) { return first }
        let usable = profileGroups.filter { $0.hasPrefix("group.") && !$0.contains("*") }
        return usable.first { $0.hasPrefix(fallbackIdentifier) } ?? usable.first ?? fallbackIdentifier
    }

    /// The App Groups a provisioning profile grants. The profile is a signed envelope around a plain XML
    /// plist, so the plist is cut out by its markers rather than verifying the signature.
    static func groups(inProvisioningProfile data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil),
              let profile = plist as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
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
