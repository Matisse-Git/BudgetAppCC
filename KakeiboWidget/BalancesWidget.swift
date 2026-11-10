import AppIntents
import SwiftUI
import WidgetKit

// The Balances widget: up to four accounts chosen per widget (touch and hold → Edit Widget).

// MARK: Configuration

/// An account as the Edit Widget screen lists it. Read from the snapshot, since the widget can't open
/// the database.
struct BalanceAccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = BalanceAccountQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct BalanceAccountQuery: EntityQuery {
    /// Archived accounts still resolve, so a widget keeps one it chose and shows it again when it's unarchived.
    func entities(for identifiers: [String]) async throws -> [BalanceAccountEntity] {
        let accounts = WidgetSnapshot.load()?.accounts ?? []
        return identifiers.compactMap { id in
            accounts.first { $0.id == id }.map { BalanceAccountEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [BalanceAccountEntity] {
        (WidgetSnapshot.load()?.accounts ?? [])
            .filter { !$0.isArchived }
            .map { BalanceAccountEntity(id: $0.id, name: $0.name) }
    }
}

struct BalancesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Balances"
    static let description = IntentDescription("Choose up to four accounts and drag them into the order you want.")

    /// Nil until the widget is edited, which shows the first four accounts.
    @Parameter(title: "Accounts", size: 4)
    var accounts: [BalanceAccountEntity]?

    init() {}
}

// MARK: Timeline

struct BalancesEntry: TimelineEntry {
    enum Problem {
        /// The app hasn't written balances yet (just updated, or the installer dropped the App Group).
        case noData
        /// There are no accounts that track a balance.
        case noAccounts
        /// The widget's list is empty.
        case noneChosen
    }

    let date: Date
    var accounts: [AccountSnapshot] = []
    var problem: Problem? = nil
    var hideWhenLocked = false

    static var sample: BalancesEntry {
        BalancesEntry(date: Date(), accounts: BalanceSelection.resolve(chosen: nil, from: WidgetSnapshot.placeholder.accounts ?? []))
    }

    static func make(chosen: [String]?, snapshot: WidgetSnapshot?, now: Date = Date()) -> BalancesEntry {
        guard let all = snapshot?.accounts else { return BalancesEntry(date: now, problem: .noData) }
        let hide = snapshot?.hideWhenLocked == true
        guard all.contains(where: { !$0.isArchived }) else {
            return BalancesEntry(date: now, problem: .noAccounts, hideWhenLocked: hide)
        }
        let shown = BalanceSelection.resolve(chosen: chosen, from: all)
        return BalancesEntry(date: now, accounts: shown, problem: shown.isEmpty ? .noneChosen : nil, hideWhenLocked: hide)
    }
}

struct BalancesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BalancesEntry { .sample }

    func snapshot(for configuration: BalancesIntent, in context: Context) async -> BalancesEntry {
        let entry = BalancesEntry.make(chosen: configuration.accounts?.map(\.id), snapshot: WidgetSnapshot.load())
        // The widget gallery shows sample accounts rather than a message.
        return entry.problem != nil && context.isPreview ? .sample : entry
    }

    func timeline(for configuration: BalancesIntent, in context: Context) async -> Timeline<BalancesEntry> {
        let entry = BalancesEntry.make(chosen: configuration.accounts?.map(\.id), snapshot: WidgetSnapshot.load())
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
    }
}

// MARK: Views

struct BalancesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BalancesEntry

    var body: some View {
        if let problem = entry.problem {
            message(problem)
        } else if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    /// One or two accounts stacked large, three or four as compact rows.
    @ViewBuilder
    private var small: some View {
        let accounts = entry.accounts
        if accounts.count <= 2 {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(accounts) { account in
                    BalanceBlock(account: account, large: accounts.count == 1, hide: entry.hideWhenLocked)
                        .frame(maxHeight: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(accounts) { account in
                    BalanceRow(account: account, hide: entry.hideWhenLocked)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    /// One account fills the widget, two sit side by side, three or four form a grid (the third spans
    /// the bottom when there is no fourth). Each account opens its own page.
    @ViewBuilder
    private var medium: some View {
        let accounts = entry.accounts
        let rows = accounts.count <= 2 ? [accounts] : [Array(accounts.prefix(2)), Array(accounts.dropFirst(2))]
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 14) {
                    ForEach(rows[index]) { account in
                        Link(destination: URL(string: "kakeibo://account/\(account.id)")!) {
                            BalanceBlock(account: account, large: accounts.count <= 2, hide: entry.hideWhenLocked)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func message(_ problem: BalancesEntry.Problem) -> some View {
        let text: (title: String, detail: String)
        switch problem {
        case .noData: text = ("Open Kakeibo", "Balances appear after the app has been opened once.")
        case .noAccounts: text = ("No accounts yet", "Add an account in Kakeibo.")
        case .noneChosen: text = ("Choose accounts", "Touch and hold, then Edit Widget.")
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("BALANCES")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(text.title)
                .font(.headline)
                .foregroundStyle(Palette.textPrimary)
            Text(text.detail)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The account's mark: its symbol in its hue, or a small card in the card's colour.
struct BalanceMark: View {
    let account: AccountSnapshot

    var body: some View {
        if account.isCredit {
            RoundedRectangle(cornerRadius: 2)
                .fill((CardColor(rawValue: account.colorKey) ?? .blue).color)
                .frame(width: 14, height: 10)
        } else {
            Image(systemName: account.symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle((Hue(rawValue: account.colorKey) ?? .blue).color)
        }
    }
}

/// The full amount. A negative bank or cash balance is red; what a card owes is plain.
struct BalanceAmount: View {
    let account: AccountSnapshot
    let hide: Bool

    var body: some View {
        Text(Yen.format(account.amount))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(account.amount < 0 && !account.isCredit ? Palette.negativeText : Palette.textPrimary)
            .privacySensitive(hide)
    }
}

/// Name above amount.
struct BalanceBlock: View {
    let account: AccountSnapshot
    let large: Bool
    let hide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                BalanceMark(account: account)
                Text(account.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            BalanceAmount(account: account, hide: hide)
                .font(large ? .title2.bold() : .headline)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Name and amount on one line; the name gives way first.
struct BalanceRow: View {
    let account: AccountSnapshot
    let hide: Bool

    var body: some View {
        HStack(spacing: 5) {
            BalanceMark(account: account)
            Text(account.name)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            BalanceAmount(account: account, hide: hide)
                .font(.caption.weight(.semibold))
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BalancesWidget: Widget {
    let kind = "KakeiboBalances"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: BalancesIntent.self, provider: BalancesProvider()) { entry in
            BalancesWidgetView(entry: entry)
                .containerBackground(Palette.card, for: .widget)
                .widgetURL(URL(string: "kakeibo://accounts"))
        }
        .configurationDisplayName("Balances")
        .description("Up to four account balances. Touch and hold to choose which.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
