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
    /// Order of the movable sections on Home, comma separated.
    static let homeSectionOrder = "homeSectionOrder"
    /// Home sections the user has hidden, comma separated.
    static let homeHiddenSections = "homeHiddenSections"
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

        if autoPayoffs, Billing.runAutoPayoffs(context: context, accounts: accounts, entries: entries, now: now) > 0 {
            try? context.save()
            entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? entries
        }

        let ledger = Ledger(accounts: accounts, categories: categories, entries: entries)
        writeWidgetSnapshot(ledger, now: now)
        BillNotifications.reschedule(ledger: ledger, now: now)
    }

    static func writeWidgetSnapshot(_ ledger: Ledger, now: Date = Date()) {
        let interval = Ledger.monthInterval(containing: now)
        let budget = ledger.categories
            .filter { $0.kind == .expense && !$0.isArchived }
            .reduce(0) { $0 + $1.monthlyBudget }
        WidgetSnapshot(
            monthTitle: now.formatted(.dateTime.month(.wide)),
            spent: ledger.totalSpending(in: interval),
            budget: budget,
            partnerOwed: ledger.partnerOwed,
            updatedAt: now
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum BillNotifications {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Local notifications at 9:00, three days and one day before a bill the paying account can't cover.
    @MainActor
    static func reschedule(ledger: Ledger, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let calendar = Calendar.kakeibo
        for reminder in Billing.reminders(ledger: ledger, now: now, windowDays: 40) where reminder.shortfall > 0 {
            for daysBefore in [3, 1] {
                guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: reminder.dueDate),
                      let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                      fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(reminder.account.name): \(Yen.format(reminder.due)) due in \(daysBefore) day\(daysBefore == 1 ? "" : "s")"
                let payer = reminder.payFrom?.name ?? "The paying account"
                content.body = "\(payer) is \(Yen.format(reminder.shortfall)) short. Top it up before \(reminder.dueDate.formatted(.dateTime.day().month(.abbreviated)))."
                content.sound = .default
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(
                    identifier: "bill-\(reminder.id)-\(daysBefore)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                )
                center.add(request, withCompletionHandler: nil)
            }
        }
    }
}
