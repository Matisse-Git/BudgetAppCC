import AppIntents
import Foundation

// Quick entries as the widget sees them. The real `QuickEntry` records live in the app's
// database, which the widget can't open, so the app publishes a copy of each one to the App Group
// and the widget hands taps back through a pending list that the app saves on its next launch.

/// A quick entry's values, copied out of the database for the widget.
struct QuickEntryCard: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var emoji: String
    var amount: Int
    var categoryID: UUID?
    /// Nil means "use the default account".
    var accountID: UUID?
    var merchant: String
    var partnerShare: Int
}

/// A widget tap the app hasn't saved yet. Holds a copy of the quick entry as it was when tapped.
struct PendingQuickEntry: Codable, Identifiable {
    /// Becomes the saved entry's ID, so saving the same tap twice can't create two entries.
    var id: UUID
    var tappedAt: Date
    var card: QuickEntryCard
}

/// How many times each quick entry was logged on `day`, as counted by the app.
struct QuickEntryCounts: Codable {
    var day: Date
    var counts: [String: Int]
}

/// The App Group side of quick entries: the published list, today's counts and pending widget taps.
struct QuickEntryStore {
    let defaults: UserDefaults

    static var shared: QuickEntryStore { QuickEntryStore(defaults: AppGroup.defaults) }

    static let cardsKey = "quickEntryCards"
    static let pendingKey = "pendingQuickEntries"
    static let countsKey = "quickEntryTodayCounts"
    /// How long the widget shows ✓ on a button after it was tapped.
    static let flashSeconds: TimeInterval = 2

    // MARK: Published list (written by the app)

    func cards() -> [QuickEntryCard] {
        decode([QuickEntryCard].self, key: Self.cardsKey) ?? []
    }

    func saveCards(_ cards: [QuickEntryCard]) {
        encode(cards, key: Self.cardsKey)
    }

    // MARK: Pending taps (written by the widget, cleared by the app)

    func pending() -> [PendingQuickEntry] {
        decode([PendingQuickEntry].self, key: Self.pendingKey) ?? []
    }

    func savePending(_ items: [PendingQuickEntry]) {
        encode(items, key: Self.pendingKey)
    }

    /// Adds a tap on the published quick entry with this ID. Returns nil if it isn't published.
    @discardableResult
    func recordTap(cardID: UUID, at date: Date = Date()) -> PendingQuickEntry? {
        guard let card = cards().first(where: { $0.id == cardID }) else { return nil }
        let tap = PendingQuickEntry(id: UUID(), tappedAt: date, card: card)
        savePending(pending() + [tap])
        return tap
    }

    /// Drops the taps the app has saved, keeping any that arrived in the meantime.
    func removePending(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        savePending(pending().filter { !ids.contains($0.id) })
    }

    // MARK: Today's counts

    func saveCounts(_ counts: [UUID: Int], day: Date) {
        let byString = Dictionary(uniqueKeysWithValues: counts.map { ($0.key.uuidString, $0.value) })
        encode(QuickEntryCounts(day: day, counts: byString), key: Self.countsKey)
    }

    /// Times this quick entry was logged today: what the app last counted plus taps it hasn't saved yet.
    func todayCount(for id: UUID, now: Date = Date(), calendar: Calendar = .current) -> Int {
        var total = 0
        if let saved = decode(QuickEntryCounts.self, key: Self.countsKey), calendar.isDate(saved.day, inSameDayAs: now) {
            total += saved.counts[id.uuidString] ?? 0
        }
        total += pending().filter { $0.card.id == id && calendar.isDate($0.tappedAt, inSameDayAs: now) }.count
        return total
    }

    /// The most recent tap, if it happened within the last `flashSeconds`.
    func recentTap(now: Date = Date()) -> PendingQuickEntry? {
        guard let last = pending().max(by: { $0.tappedAt < $1.tappedAt }) else { return nil }
        let age = now.timeIntervalSince(last.tappedAt)
        return age >= 0 && age < Self.flashSeconds ? last : nil
    }

    // MARK: Coding

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Run by a quick-entry button on the widget. Only records the tap; the app saves it as an
/// entry the next time it opens. Hidden from Shortcuts, which has its own "Log Quick Entry" action.
struct LogQuickEntryFromWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Quick Entry from Widget"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Quick entry ID")
    var quickEntryID: String

    init() {}

    init(quickEntryID: UUID) {
        self.quickEntryID = quickEntryID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: quickEntryID) {
            QuickEntryStore.shared.recordTap(cardID: id)
        }
        return .result()
    }
}
