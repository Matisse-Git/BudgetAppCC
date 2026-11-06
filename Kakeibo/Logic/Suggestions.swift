import Foundation

/// Pre-picks the add sheet from history, so most entries are amount → Save.
enum Suggestions {
    /// How far back history counts.
    static let lookbackDays: Double = 120

    /// The category most likely wanted at `date`: past entries of the same kind at a similar time of day
    /// and on the same kind of day (weekday or weekend), with recent ones counting more. Ties go to the
    /// category that comes first in the user's order. Nil without history.
    static func category(kind: EntryKind, at date: Date, entries: [Entry], categories: [BudgetCategory],
                         calendar: Calendar = .kakeibo) -> UUID? {
        let wanted: CategoryKind = kind == .income ? .income : .expense
        let candidates = categories.filter { $0.kind == wanted && !$0.isArchived }
        let valid = Set(candidates.map(\.id))
        let minute = minuteOfDay(date, calendar: calendar)
        let weekend = calendar.isDateInWeekend(date)

        var scores: [UUID: Double] = [:]
        for entry in entries where entry.kind == kind && entry.date <= date {
            guard let id = entry.categoryID, valid.contains(id) else { continue }
            let age = date.timeIntervalSince(entry.date) / 86_400
            guard age <= lookbackDays else { continue }
            let recency = pow(0.5, age / 30)
            let gap = abs(minuteOfDay(entry.date, calendar: calendar) - minute)
            let distance = min(gap, 1_440 - gap)
            let timeOfDay = distance <= 90 ? 1.0 : (distance <= 180 ? 0.5 : 0.15)
            let sameKindOfDay = calendar.isDateInWeekend(entry.date) == weekend ? 1.2 : 1.0
            scores[id, default: 0] += recency * timeOfDay * sameKindOfDay
        }

        var best: (id: UUID, score: Double)?
        for category in candidates.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let score = scores[category.id], score > 0 else { continue }
            if best == nil || score > best!.score { best = (category.id, score) }
        }
        return best?.id
    }

    /// The account last used with this category, if it's still active and holds a balance.
    static func account(forCategory categoryID: UUID?, kind: EntryKind, entries: [Entry], accounts: [Account]) -> UUID? {
        guard let categoryID else { return nil }
        let usable = Set(accounts.filter { !$0.isArchived && $0.tracksBalance }.map(\.id))
        let latest = entries
            .filter { $0.kind == kind && $0.categoryID == categoryID && $0.accountID.map(usable.contains) == true }
            .max { $0.date < $1.date }
        return latest?.accountID
    }

    /// Categories of a kind, most used in the last 90 days first, then in the user's order.
    static func rankedCategories(kind: CategoryKind, entries: [Entry], categories: [BudgetCategory], now: Date = Date()) -> [BudgetCategory] {
        let since = now.addingTimeInterval(-90 * 86_400)
        var counts: [UUID: Int] = [:]
        for entry in entries where entry.date >= since && entry.date <= now {
            if let id = entry.categoryID { counts[id, default: 0] += 1 }
        }
        return categories
            .filter { $0.kind == kind && !$0.isArchived }
            .sorted { (-(counts[$0.id] ?? 0), $0.sortOrder) < (-(counts[$1.id] ?? 0), $1.sortOrder) }
    }

    /// The tiles shown in the add sheet: the `limit` most used (plus the selected one), in the user's
    /// order so tiles don't jump around from day to day.
    static func tiles(kind: CategoryKind, selected: UUID?, limit: Int, entries: [Entry], categories: [BudgetCategory],
                      now: Date = Date()) -> [BudgetCategory] {
        let ranked = rankedCategories(kind: kind, entries: entries, categories: categories, now: now)
        guard ranked.count > limit else { return ranked.sorted { $0.sortOrder < $1.sortOrder } }
        var picked = Array(ranked.prefix(limit))
        if let selected, !picked.contains(where: { $0.id == selected }),
           let chosen = ranked.first(where: { $0.id == selected }) {
            picked[picked.count - 1] = chosen
        }
        return picked.sorted { $0.sortOrder < $1.sortOrder }
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
