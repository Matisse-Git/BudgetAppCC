import Foundation
import SwiftData
import UserNotifications
import WidgetKit

enum SettingsKey {
    static let defaultAccountID = "defaultAccountID"
    static let setupDone = "setupDone"
    static let seeded = "seeded"
    static let partnerName = "partnerName"
    /// Stored for later payday-based months; v1 always uses calendar months.
    static let monthStartDay = "monthStartDay"
    /// Show shortfall warnings on Summary and send their notifications (on by default).
    static let shortfallWarnings = "shortfallWarnings"
    /// Pre-pick category and account in the add sheet from history (on by default).
    static let suggestCategory = "suggestCategory"
    /// Taps on the add sheet's keypad (on by default; iOS's System Haptics switch still wins).
    static let keypadHaptics = "keypadHaptics"
    /// Remind 3 days before every card payment (on by default; each card can opt out).
    static let billReminders = "billReminders"
    /// A daily "Anything else to log?" notification (off by default) and its time in minutes after midnight.
    static let eveningReminder = "eveningReminder"
    static let eveningReminderMinutes = "eveningReminderMinutes"
    /// Cover the app with a blank screen in the app switcher (on by default).
    static let hideInSwitcher = "hideInSwitcher"
    /// Ask for Face ID (or the passcode) when Kakeibo opens (off by default).
    static let faceIDLock = "faceIDLock"
    /// When the last full backup was exported.
    static let lastBackup = "lastBackup"
    /// Accounts tab: split non-credit accounts into Bank, Top-up and Cash. Off shows one "Money" list.
    static let groupAccountsByType = "groupAccountsByType"

    static let defaultPartnerName = "Girlfriend"
}

/// Where the app keeps its database: its own container, which survives AltStore refreshes.
@MainActor
final class AppData {
    static let shared = AppData()

    let container: ModelContainer

    private init() {
        let schema = Schema([Account.self, BudgetCategory.self, Entry.self])
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configuration = DemoMode.isOn
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(schema: schema, url: folder.appending(path: "Kakeibo.store"), cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the Kakeibo database: \(error)")
        }
    }
}

extension ModelContext {
    /// Saves and updates everything derived from the data (widget, bill notifications).
    @MainActor
    func saveAndRefresh() {
        do { try save() } catch { print("Save failed: \(error)") }
        Maintenance.run(self, autoPayoffs: false)
    }
}

@MainActor
enum Maintenance {
    static func run(_ context: ModelContext, autoPayoffs: Bool = true, now: Date = Date()) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<BudgetCategory>())) ?? []
        var entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []

        var paid: [Entry] = []
        if autoPayoffs, Billing.runAutoPayoffs(context: context, accounts: accounts, entries: entries, now: now,
                                                onCreate: { paid.append($0) }) > 0 {
            try? context.save()
            entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? entries
        }

        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        writeWidgetSnapshot(ledger, now: now)
        BillNotifications.reschedule(ledger: ledger, now: now)
        BillNotifications.announcePayments(paid, ledger: ledger, now: now)
        BillNotifications.scheduleEveningReminder()
    }

    static func writeWidgetSnapshot(_ ledger: Ledger, now: Date = Date()) {
        let pace = BudgetPace(ledger: ledger, month: now, now: now)
        let status: String
        switch pace.status {
        case .onTrack: status = "onTrack"
        case .atRisk: status = "atRisk"
        case .over: status = "over"
        }
        let alert = pace.needsAttention.first.map { item in
            item.status == .over
                ? "\(item.category.name) \(Yen.format(item.spent - item.budget)) over"
                : "\(item.category.name) \(Yen.format(item.left)) left"
        }
        let bill = Billing.reminders(ledger: ledger, now: now).first.map { reminder in
            NextBillSnapshot(cardName: reminder.account.name, colorKey: AccountLook.cardColor(reminder.account).rawValue,
                             amount: reminder.due, dueDate: reminder.dueDate, payerName: reminder.payFrom?.name,
                             shortfall: reminder.shortfall)
        }
        WidgetSnapshot(
            monthTitle: now.formatted(.dateTime.month(.wide)),
            spent: pace.spent,
            budget: pace.budget,
            partnerOwed: ledger.partnerOwed,
            updatedAt: now,
            daysElapsed: pace.daysElapsed,
            daysInMonth: pace.daysInMonth,
            perDay: pace.perDay,
            paceStatus: status,
            alert: alert,
            nextBill: bill
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum BillNotifications {
    private static let scheduledKey = "scheduledBillNotifications"
    private static let announcedKey = "announcedStatements"
    private static let eveningID = "evening-reminder"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Card bill notifications, all local and scheduled on the device:
    /// - when a statement closes: "statement closed", or "bill not covered" if the paying account will be short;
    /// - 3 and 1 days before a bill that won't be covered, at 9:00;
    /// - 3 days before every other bill, at 9:00.
    /// Only Kakeibo's own bill requests are replaced, so the evening reminder survives.
    @MainActor
    static func reschedule(ledger: Ledger, now: Date = Date(), defaults: UserDefaults = .standard) {
        let center = UNUserNotificationCenter.current()
        let previous = defaults.stringArray(forKey: scheduledKey) ?? []
        center.removePendingNotificationRequests(withIdentifiers: previous)

        let warnShortfalls = defaults.object(forKey: SettingsKey.shortfallWarnings) as? Bool ?? true
        let remindBills = defaults.object(forKey: SettingsKey.billReminders) as? Bool ?? true
        var announced = Set(defaults.stringArray(forKey: announcedKey) ?? [])
        var scheduled: [String] = []
        let calendar = Calendar.kakeibo

        for reminder in Billing.reminders(ledger: ledger, now: now) where !reminder.isOverdue {
            let card = reminder.account
            let payer = reminder.payFrom?.name ?? "The paying account"
            let due = reminder.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let short = warnShortfalls && reminder.shortfall > 0

            // Once per statement, soon after it closes (not for old statements on a first run).
            let closedRecently = now.timeIntervalSince(reminder.cycle.closingBoundary) < 2 * 86_400
            if !announced.contains(reminder.id) {
                announced.insert(reminder.id)
                if closedRecently {
                    let content = UNMutableNotificationContent()
                    if short {
                        content.title = "\(card.name) bill not covered"
                        content.body = "\(payer) is \(Yen.format(reminder.shortfall)) short for the \(Yen.format(reminder.due)) payment on \(due)."
                    } else {
                        content.title = "\(card.name) statement closed"
                        content.body = reminder.payFrom == nil
                            ? "\(Yen.format(reminder.due)) is due \(due)."
                            : "\(Yen.format(reminder.due)) is due \(due). \(payer) covers it."
                    }
                    content.sound = .default
                    let id = "bill-closed-\(reminder.id)"
                    let request = UNNotificationRequest(identifier: id, content: content,
                                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
                    center.add(request, withCompletionHandler: nil)
                }
            }

            let fireDates: [Date]
            if short && card.shortfallWarning {
                fireDates = Billing.reminderDates(dueDate: reminder.dueDate, now: now, calendar: calendar)
            } else if remindBills && card.paymentReminder {
                fireDates = Array(Billing.reminderDates(dueDate: reminder.dueDate, now: now, calendar: calendar).prefix(1))
                    .filter { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: reminder.dueDate).day == 3 }
            } else {
                fireDates = []
            }
            for fire in fireDates {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: fire), to: reminder.dueDate).day ?? 0
                let content = UNMutableNotificationContent()
                if short {
                    content.title = "\(card.name) bill not covered"
                    content.body = "\(payer) is \(Yen.format(reminder.shortfall)) short for the \(Yen.format(reminder.due)) payment on \(due)."
                } else {
                    content.title = "\(card.name) bill in \(days) day\(days == 1 ? "" : "s")"
                    content.body = reminder.payFrom == nil
                        ? "\(Yen.format(reminder.due)) is due \(due)."
                        : "\(Yen.format(reminder.due)) is due \(due) from \(payer)."
                }
                content.sound = .default
                let id = "bill-\(reminder.id)-\(days)"
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(identifier: id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                center.add(request, withCompletionHandler: nil)
                scheduled.append(id)
            }
        }
        defaults.set(scheduled, forKey: scheduledKey)
        defaults.set(Array(announced.suffix(200)), forKey: announcedKey)
    }

    /// "Everyday Card paid: ¥86,420 recorded as a transfer from Main Bank, which now has ¥416,610."
    @MainActor
    static func announcePayments(_ payoffs: [Entry], ledger: Ledger, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        for payoff in payoffs {
            guard let card = ledger.account(payoff.toAccountID), let bank = ledger.account(payoff.accountID) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(card.name) paid"
            content.body = "\(Yen.format(payoff.amount)) recorded as a transfer from \(bank.name), which now has \(Yen.format(ledger.balance(of: bank, before: now)))."
            let request = UNNotificationRequest(identifier: "paid-\(payoff.id.uuidString)", content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
            center.add(request, withCompletionHandler: nil)
        }
    }

    /// The daily "Anything else to log?" nudge, if it's on.
    static func scheduleEveningReminder(defaults: UserDefaults = .standard) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [eveningID])
        guard defaults.bool(forKey: SettingsKey.eveningReminder) else { return }
        let minutes = defaults.object(forKey: SettingsKey.eveningReminderMinutes) as? Int ?? 21 * 60
        let content = UNMutableNotificationContent()
        content.title = "Anything else to log?"
        content.body = "Add today's spending in a few seconds."
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: minutes / 60, minute: minutes % 60), repeats: true)
        center.add(UNNotificationRequest(identifier: eveningID, content: content, trigger: trigger), withCompletionHandler: nil)
    }
}
