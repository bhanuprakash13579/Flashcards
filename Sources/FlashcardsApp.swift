import SwiftUI
import SwiftData
import UserNotifications

@main
struct FlashcardsApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([Deck.self, Card.self, Tag.self])
        // 1. Try CloudKit-backed store.
        if let c = try? ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        ]) {
            container = c
            return
        }
        // 2. Fall back to local persistent store.
        if let c = try? ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        ]) {
            container = c
            return
        }
        // 3. Last resort: in-memory store so the app never crashes on launch.
        // Data won't persist across launches in this state, but the app remains usable.
        container = try! ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    var body: some Scene {
        WindowGroup {
            DecksListView()
                .task {
                    cleanupRecycleBin()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                _ = try? AutoBackupService.runBackup(context: container.mainContext)
                refreshWidget()
            } else if phase == .active {
                refreshWidget()
                indexSpotlight()
                rescheduleNotificationWithDueCount()
                clearNotificationBadge()
            }
        }
    }
    
    private func rescheduleNotificationWithDueCount() {
        let ctx = container.mainContext
        let allDecks = (try? ctx.fetch(FetchDescriptor<Deck>(
            predicate: #Predicate { $0.isDeleted == false }
        ))) ?? []
        let due = allDecks.reduce(0) { $0 + $1.dueCount }
        Task {
            guard let comps = await NotificationService.currentDailyReminderTime(),
                  let hour = comps.hour, let minute = comps.minute else { return }
            await NotificationService.scheduleDailyReminder(hour: hour, minute: minute, dueCount: due)
        }
    }

    private func clearNotificationBadge() {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    private func refreshWidget() {
        let ctx = container.mainContext
        let allDecks = (try? ctx.fetch(FetchDescriptor<Deck>(
            predicate: #Predicate { $0.isDeleted == false }
        ))) ?? []
        let due = allDecks.reduce(0) { $0 + $1.dueCount }
        WidgetDataStore.write(dueCount: due)
    }

    private func indexSpotlight() {
        let ctx = container.mainContext
        let decks = (try? ctx.fetch(FetchDescriptor<Deck>())) ?? []
        SpotlightService.indexDecks(decks)
    }

    private func cleanupRecycleBin() {
        let ctx = container.mainContext
        let threshold = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let desc = FetchDescriptor<Deck>(predicate: #Predicate<Deck> { $0.isDeleted == true })
        if let deletedDecks = try? ctx.fetch(desc) {
            for deck in deletedDecks {
                if let delDate = deck.deletedAt, delDate < threshold {
                    ctx.delete(deck)
                }
            }
            try? ctx.save()
        }
    }
}
