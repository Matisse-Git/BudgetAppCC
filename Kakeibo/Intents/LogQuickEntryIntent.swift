import AppIntents
import Foundation
import SwiftData

/// A quick entry as Shortcuts sees it.
struct QuickEntryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Quick Entry"
    static let defaultQuery = QuickEntryQuery()

    let id: UUID
    let name: String
    let emoji: String
    let amount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: "\(emoji) \(name)"),
            subtitle: LocalizedStringResource(stringLiteral: Yen.format(amount))
        )
    }

    @MainActor
    static func all() -> [QuickEntryEntity] {
        let context = AppData.shared.container.mainContext
        let stored = (try? context.fetch(FetchDescriptor<QuickEntry>())) ?? []
        return QuickEntries.sorted(stored).map {
            QuickEntryEntity(id: $0.id, name: $0.name, emoji: $0.emoji, amount: $0.amount)
        }
    }
}

struct QuickEntryQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [QuickEntryEntity] {
        await MainActor.run { QuickEntryEntity.all().filter { identifiers.contains($0.id) } }
    }

    func suggestedEntities() async throws -> [QuickEntryEntity] {
        await MainActor.run { QuickEntryEntity.all() }
    }
}

/// Logs one of your quick entries right away, without opening the app.
struct LogQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Quick Entry"
    static let description: IntentDescription? = IntentDescription("Saves one of your Kakeibo quick entries as an expense, dated now.")

    @Parameter(title: "Quick entry")
    var quickEntry: QuickEntryEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$quickEntry)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppData.shared.container.mainContext
        let stored = (try? context.fetch(FetchDescriptor<QuickEntry>())) ?? []
        guard let match = stored.first(where: { $0.id == quickEntry.id }) else {
            return .result(dialog: IntentDialog(stringLiteral: "That quick entry no longer exists."))
        }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let card = match.card
        let entry = QuickEntries.makeEntry(
            from: card, at: Date(),
            accountID: QuickEntries.accountID(for: card, accounts: accounts, defaultAccountID: QuickEntries.defaultAccountID)
        )
        context.insert(entry)
        context.saveAndRefresh()
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(match.name), \(Yen.format(match.amount))."))
    }
}
