import Foundation

/// Days Japanese banks are closed: weekends, national holidays (祝日), substitute holidays (振替休日),
/// citizens' holidays (国民の休日) and the year-end closure (Dec 31 – Jan 3).
///
/// Rules follow the Public Holiday Act as amended in 2018. Equinoxes use the standard approximation,
/// good for 1980–2099; the one-off moves of 2019–2021 are built in. Card payments that land on a closed
/// day move to the next (or previous) business day, which is what `Billing` uses this for.
enum JapaneseHolidays {
    /// Name of the holiday or bank closure on `date`, nil for an ordinary day (weekends aren't holidays).
    static func name(of date: Date, calendar: Calendar = .kakeibo) -> String? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return table(for: year, calendar: calendar)[month * 100 + day]
    }

    static func isBankHoliday(_ date: Date, calendar: Calendar = .kakeibo) -> Bool {
        name(of: date, calendar: calendar) != nil
    }

    static func isWeekend(_ date: Date, calendar: Calendar = .kakeibo) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    static func isBusinessDay(_ date: Date, calendar: Calendar = .kakeibo) -> Bool {
        !isWeekend(date, calendar: calendar) && !isBankHoliday(date, calendar: calendar)
    }

    /// `date` itself if banks are open, otherwise the next day they are. Returns the start of that day.
    static func nextBusinessDay(onOrAfter date: Date, calendar: Calendar = .kakeibo) -> Date {
        step(from: date, by: 1, calendar: calendar)
    }

    /// `date` itself if banks are open, otherwise the last day before it that they were.
    static func previousBusinessDay(onOrBefore date: Date, calendar: Calendar = .kakeibo) -> Date {
        step(from: date, by: -1, calendar: calendar)
    }

    /// National, substitute and citizens' holidays plus bank closures in `year`, sorted, as (month, day, name).
    static func holidays(in year: Int, calendar: Calendar = .kakeibo) -> [(month: Int, day: Int, name: String)] {
        table(for: year, calendar: calendar)
            .sorted { $0.key < $1.key }
            .map { (month: $0.key / 100, day: $0.key % 100, name: $0.value) }
    }

    // MARK: Building a year

    private static func step(from date: Date, by direction: Int, calendar: Calendar) -> Date {
        var day = calendar.startOfDay(for: date)
        // Japan never has more than a handful of closed days in a row; the cap only guards against bad input.
        for _ in 0..<14 {
            if isBusinessDay(day, calendar: calendar) { return day }
            guard let next = calendar.date(byAdding: .day, value: direction, to: day) else { break }
            day = next
        }
        return day
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var years: [String: [Int: String]] = [:]
    }

    private static let cache = Cache()

    /// Holidays keyed by month × 100 + day.
    private static func table(for year: Int, calendar: Calendar) -> [Int: String] {
        let key = "\(year)-\(calendar.timeZone.identifier)"
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let cached = cache.years[key] { return cached }
        let built = build(year, calendar: calendar)
        cache.years[key] = built
        return built
    }

    private static func build(_ year: Int, calendar: Calendar) -> [Int: String] {
        var national: [Int: String] = [:]
        func add(_ month: Int, _ day: Int, _ name: String) { national[month * 100 + day] = name }

        add(1, 1, "New Year's Day")
        add(1, nthMonday(2, month: 1, year: year, calendar: calendar), "Coming of Age Day")
        add(2, 11, "National Foundation Day")
        if year >= 2020 { add(2, 23, "Emperor's Birthday") }
        add(3, vernalEquinox(year), "Vernal Equinox Day")
        add(4, 29, "Shōwa Day")
        add(5, 3, "Constitution Memorial Day")
        add(5, 4, "Greenery Day")
        add(5, 5, "Children's Day")
        switch year {
        case 2020: add(7, 23, "Marine Day")
        case 2021: add(7, 22, "Marine Day")
        default: add(7, nthMonday(3, month: 7, year: year, calendar: calendar), "Marine Day")
        }
        switch year {
        case 2020: add(8, 10, "Mountain Day")
        case 2021: add(8, 8, "Mountain Day")
        default: if year >= 2016 { add(8, 11, "Mountain Day") }
        }
        add(9, nthMonday(3, month: 9, year: year, calendar: calendar), "Respect for the Aged Day")
        add(9, autumnalEquinox(year), "Autumnal Equinox Day")
        switch year {
        case 2020: add(7, 24, "Sports Day")
        case 2021: add(7, 23, "Sports Day")
        default: add(10, nthMonday(2, month: 10, year: year, calendar: calendar), "Sports Day")
        }
        add(11, 3, "Culture Day")
        add(11, 23, "Labour Thanksgiving Day")
        if year <= 2018 { add(12, 23, "Emperor's Birthday") }
        if year == 2019 {
            add(5, 1, "Enthronement Day")
            add(10, 22, "Enthronement Ceremony")
        }

        var result = national

        // 振替休日: a holiday on a Sunday moves to the next day that isn't already a holiday.
        for key in national.keys.sorted() {
            guard let date = makeDate(year, key, calendar), calendar.component(.weekday, from: date) == 1 else { continue }
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while let k = monthDayKey(next, year: year, calendar: calendar), result[k] != nil {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            }
            if let k = monthDayKey(next, year: year, calendar: calendar) { result[k] = "Substitute Holiday" }
        }

        // 国民の休日: an ordinary day squeezed between two national holidays is a holiday too.
        let sorted = national.keys.sorted()
        for (first, second) in zip(sorted, sorted.dropFirst()) {
            guard let a = makeDate(year, first, calendar), let b = makeDate(year, second, calendar),
                  calendar.dateComponents([.day], from: a, to: b).day == 2,
                  let middle = calendar.date(byAdding: .day, value: 1, to: a),
                  let k = monthDayKey(middle, year: year, calendar: calendar),
                  result[k] == nil,
                  calendar.component(.weekday, from: middle) != 1 else { continue }
            result[k] = "Citizens' Holiday"
        }

        // Banks also close for the new year.
        for key in [102, 103, 1231] where result[key] == nil {
            result[key] = "Bank holiday"
        }
        return result
    }

    private static func makeDate(_ year: Int, _ key: Int, _ calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: key / 100, day: key % 100))
    }

    /// month × 100 + day, or nil once the date leaves `year`.
    private static func monthDayKey(_ date: Date, year: Int, calendar: Calendar) -> Int? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard parts.year == year, let month = parts.month, let day = parts.day else { return nil }
        return month * 100 + day
    }

    /// Day of the month of the `n`th Monday.
    private static func nthMonday(_ n: Int, month: Int, year: Int, calendar: Calendar) -> Int {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let weekday = calendar.component(.weekday, from: first) // 1 = Sunday, 2 = Monday
        return 1 + (9 - weekday) % 7 + (n - 1) * 7
    }

    private static func vernalEquinox(_ year: Int) -> Int {
        let y = Double(year - 1980)
        return Int(20.8431 + 0.242194 * y - floor(y / 4))
    }

    private static func autumnalEquinox(_ year: Int) -> Int {
        let y = Double(year - 1980)
        return Int(23.2488 + 0.242194 * y - floor(y / 4))
    }
}
