import Foundation
import SwiftData

/// Turning quick entries into entries, saving widget taps, and publishing the list for the widget.
enum QuickEntries {
    /// The account a quick entry logs to: its own account if it still exists (archived or not),
    /// otherwise the default account.
    static func accountID(for card: QuickEntryCard, accounts: [Account], defaultAccountID: UUID?) -> UUID? {
        if let id = card.accountID, accounts.contains(where: { $0.id == id }) { return id }
        return defaultAccountID
    }

    /// An expense from a quick entry. The note is the quick entry's name.
    static func makeEntry(from card: QuickEntryCard, at date: Date, accountID: UUID?) -> Entry {
        let entry = Entry(kind: .expense, amount: card.amount, date: date, accountID: accountID, categoryID: card.categoryID)
        entry.note = card.name
        entry.merchant = card.merchant
        entry.partnerShare = min(max(card.partnerShare, 0), card.amount)
        entry.quickEntryID = card.id
        return entry
    }

    /// Saves widget taps waiting in the App Group as entries dated when they were tapped.
    /// A tap whose entry already exists is skipped, so running this twice never doubles up.
    /// Returns how many entries were added.
    @MainActor
    @discardableResult
    static func savePendingTaps(into context: ModelContext, store: QuickEntryStore, defaultAccountID: UUID?) -> Int {
        let pending = store.pending()
        guard !pending.isEmpty else { return 0 }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let existing = Set(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).map(\.id))
        var added = 0
        for tap in pending where !existing.contains(tap.id) {
            let entry = makeEntry(from: tap.card, at: tap.tappedAt,
                                  accountID: accountID(for: tap.card, accounts: accounts, defaultAccountID: defaultAccountID))
            entry.id = tap.id
            context.insert(entry)
            added += 1
        }
        if added > 0 {
            do {
                try context.save()
            } catch {
                // Keep the taps for next time rather than lose them.
                print("Saving quick entries failed: \(error)")
                return 0
            }
        }
        store.removePending(ids: Set(pending.map(\.id)))
        return added
    }

    /// How many entries came from each quick entry on the day of `now`.
    static func todayCounts(entries: [Entry], now: Date, calendar: Calendar = .current) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for entry in entries {
            guard let id = entry.quickEntryID, calendar.isDate(entry.date, inSameDayAs: now) else { continue }
            counts[id, default: 0] += 1
        }
        return counts
    }

    /// Writes the quick entries (in Settings order) and today's counts to the App Group for the widget.
    static func publish(_ quickEntries: [QuickEntry], entries: [Entry], store: QuickEntryStore, now: Date = Date()) {
        store.saveCards(sorted(quickEntries).map(\.card))
        store.saveCounts(todayCounts(entries: entries, now: now), day: Calendar.current.startOfDay(for: now))
    }

    static func sorted(_ quickEntries: [QuickEntry]) -> [QuickEntry] {
        quickEntries.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    /// The default account from Settings.
    static var defaultAccountID: UUID? {
        UserDefaults.standard.string(forKey: SettingsKey.defaultAccountID).flatMap(UUID.init(uuidString:))
    }
}
