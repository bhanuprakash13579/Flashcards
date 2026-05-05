import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var decks: [Deck]
    @Query private var cards: [Card]

    @State private var exporting = false
    @State private var importing = false
    @State private var folderPicking = false
    @State private var exportDocument: BackupDocument?
    @State private var exportFilename = "flashcards-backup.json"
    @State private var pendingImportURL: URL?
    @State private var showImportChoice = false
    @State private var resultMessage: String?

    @AppStorage("dailyReminderEnabled") private var reminderEnabled = false
    @AppStorage("dailyReminderHour") private var reminderHour = 19
    @AppStorage("dailyReminderMinute") private var reminderMinute = 0
    @AppStorage("dailyReviewGoal") private var dailyReviewGoal = 20
    @AppStorage("practiceRoundSize") private var practiceRoundSize = PracticeQueue.defaultRoundSize
    @AppStorage("dailyNewCardLimit") private var dailyNewCardLimit = PracticeQueue.defaultDailyNewCardLimit
    @AppStorage("neverForgetEnabled") private var neverForgetEnabled = false
    @AppStorage("timedPracticeEnabled") private var timedPracticeEnabled = false
    @AppStorage("fsrsTargetRetention") private var fsrsTargetRetention = 0.9
    @AppStorage("claudeAPIKey") private var claudeAPIKey = ""

    @State private var reminderTime = Date()
    @State private var permissionDenied = false
    @State private var autoBackupRefreshTick = 0
    @State private var isWorking = false
    @State private var claudeKeyDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                librarySection
                studySection
                aiSection
                cloudBackupSection
                manualBackupSection
                remindersSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $exporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { result in
                switch result {
                case .success: resultMessage = "Backup saved."
                case .failure(let e): resultMessage = "Export failed: \(e.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        pendingImportURL = url
                        showImportChoice = true
                    }
                case .failure(let e):
                    resultMessage = "Import failed: \(e.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $folderPicking,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderPick(result)
            }
            .confirmationDialog(
                "How should the backup be applied?",
                isPresented: $showImportChoice,
                titleVisibility: .visible
            ) {
                Button("Merge with current library") { runImport(.mergeUpsert) }
                Button("Replace everything", role: .destructive) { runImport(.replaceAll) }
                Button("Cancel", role: .cancel) { pendingImportURL = nil }
            } message: {
                Text("Merge keeps existing decks and updates the rest. Replace deletes all current data first.")
            }
            .alert("Done", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            ), presenting: resultMessage) { _ in
                Button("OK") { resultMessage = nil }
            } message: { msg in
                Text(msg)
            }
            .overlay {
                if isWorking {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(1.4)
                            Text("Importing…")
                                .foregroundStyle(.white)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(32)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .onAppear { syncReminderState() }
        }
    }

    // MARK: - Sections

    private var librarySection: some View {
        Section("Library") {
            LabeledContent("Decks", value: "\(decks.filter { !$0.isDeleted }.count)")
            LabeledContent("Cards", value: "\(cards.count)")
            NavigationLink("Recycle Bin") {
                RecycleBinView(onRestore: { dismiss() })
            }
        }
    }

    private var studySection: some View {
        Section {
            Stepper(value: $practiceRoundSize, in: 5...100, step: 5) {
                HStack {
                    Text("Cards per round")
                    Spacer()
                    Text("\(practiceRoundSize)").foregroundStyle(.secondary)
                }
            }
            Stepper(value: $dailyNewCardLimit, in: 5...100, step: 5) {
                HStack {
                    Text("New cards per day")
                    Spacer()
                    Text("\(dailyNewCardLimit)").foregroundStyle(.secondary)
                }
            }
            Stepper(value: $dailyReviewGoal, in: 5...200, step: 5) {
                HStack {
                    Text("Daily review goal")
                    Spacer()
                    Text("\(dailyReviewGoal)").foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $neverForgetEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Never-Forget mode")
                    Text("Forces all Hard / struggling cards to the front of each session until reviewed today.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $timedPracticeEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timed practice")
                    Text("Shows a per-card countdown based on question type. Legal/Verbal: 25s · Factual: 28s · Arithmetic: 50s.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Review depth")
                    Spacer()
                    Text(String(format: "%.0f%%", fsrsTargetRetention * 100))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $fsrsTargetRetention, in: 0.80...0.95, step: 0.01)
                    .tint(fsrsTargetRetention >= 0.92 ? Theme.stretch :
                          fsrsTargetRetention >= 0.87 ? .orange : Theme.success)
                Text(fsrsTargetRetention >= 0.92
                     ? "Exam mode — maximum retention, more frequent reviews."
                     : fsrsTargetRetention >= 0.87
                     ? "Balanced — good for active study periods."
                     : "Light — fewer reviews, more new cards each day.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Study load")
        } footer: {
            Text("New cards per day: caps how many unseen cards are introduced each day — prevents overload on large decks. Cards per round: limits one session. Daily goal: your total review target.")
        }
    }

    private var cloudBackupSection: some View {
        let _ = autoBackupRefreshTick   // re-read on tick
        return Section {
            if AutoBackupService.hasFolder, let name = AutoBackupService.folderDisplayName {
                LabeledContent("Folder") {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
                if let last = AutoBackupService.lastBackupDate {
                    LabeledContent("Last backup") {
                        Text(last, style: .relative).foregroundStyle(.secondary)
                    }
                }
                Button {
                    runAutoBackupNow()
                } label: {
                    Label("Back up now", systemImage: "arrow.clockwise.icloud")
                }
                Button {
                    runRestoreFromAutoBackup()
                } label: {
                    Label("Restore from this folder", systemImage: "arrow.down.doc")
                }
                Button(role: .destructive) {
                    AutoBackupService.clearFolder()
                    autoBackupRefreshTick += 1
                } label: {
                    Label("Disconnect folder", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    folderPicking = true
                } label: {
                    Label("Pick a Drive / Dropbox / OneDrive folder", systemImage: "folder.badge.plus")
                }
            }
        } header: {
            Text("Auto-backup folder")
        } footer: {
            Text("Pick any folder inside the iOS Files app — Google Drive, Dropbox, OneDrive, on-device, anywhere. The app keeps a single `flashcards-backup.json` file there and refreshes it whenever you leave the app. Your cloud provider syncs it automatically. No accounts, no SDK, free.")
        }
    }

    private var aiSection: some View {
        Section {
            if claudeAPIKey.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a Claude API key to use AI card generation inside any deck.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("sk-ant-…", text: $claudeKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        claudeAPIKey = claudeKeyDraft.trimmingCharacters(in: .whitespaces)
                        claudeKeyDraft = ""
                    }
                    .disabled(claudeKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.vertical, 4)
            } else {
                LabeledContent("Claude API key") {
                    HStack {
                        Text("••••" + String(claudeAPIKey.suffix(4)))
                            .foregroundStyle(.secondary).font(.caption)
                        Button("Clear") { claudeAPIKey = "" }
                            .font(.caption)
                    }
                }
            }
        } header: {
            Text("AI card generation")
        } footer: {
            Text("Get a free API key at console.anthropic.com. Used only for generating flashcards on-device — never stored on our servers.")
        }
    }

    private var manualBackupSection: some View {
        Section {
            Button {
                prepareExport()
            } label: {
                Label("Export backup (JSON)", systemImage: "square.and.arrow.up")
            }
            Button {
                importing = true
            } label: {
                Label("Import / Restore from file", systemImage: "square.and.arrow.down")
            }
            .disabled(isWorking)
        } header: {
            Text("Manual backup")
        } footer: {
            Text("Useful for one-off snapshots or moving between devices.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Daily reminder", isOn: Binding(
                get: { reminderEnabled },
                set: { newValue in Task { await toggleReminder(newValue) } }
            ))
            if reminderEnabled {
                DatePicker("Time",
                           selection: $reminderTime,
                           displayedComponents: .hourAndMinute)
                    .onChange(of: reminderTime) { _, new in
                        Task { await rescheduleReminder(for: new) }
                    }
            }
            if permissionDenied {
                Text("Notifications are blocked. Enable them in iOS Settings → Flashcards → Notifications.")
                    .font(.caption).foregroundStyle(Theme.destructive)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Pick a time you actually have free — implementation intentions (\"I'll review at 7pm\") roughly double follow-through versus vague good intentions.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func prepareExport() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let backup = try BackupService.snapshot(context: ctx)
                let data = try await Task.detached(priority: .userInitiated) {
                    try BackupService.encode(backup)
                }.value
                exportDocument = BackupDocument(data: data)
                exportFilename = "flashcards-\(stampedFilename()).json"
                exporting = true
            } catch {
                resultMessage = "Could not build backup: \(error.localizedDescription)"
            }
        }
    }

    private func stampedFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: Date())
    }

    private func runImport(_ mode: BackupService.MergeMode) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                // File I/O + JSON decode off the main thread
                let backup = try await Task.detached(priority: .userInitiated) {
                    try BackupService.loadBackupFile(from: url)
                }.value
                let container = ctx.container
                let r = try await Task.detached(priority: .userInitiated) {
                    let actor = ImportActor(modelContainer: container)
                    return try await actor.apply(backup: backup, mode: mode)
                }.value
                resultMessage = "Imported \(r.decks) decks · \(r.cards) cards."
            } catch {
                resultMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try AutoBackupService.setFolder(url)
                runAutoBackupNow()
            } catch {
                resultMessage = "Couldn't connect that folder: \(error.localizedDescription)"
            }
        case .failure(let e):
            resultMessage = "Pick failed: \(e.localizedDescription)"
        }
    }

    private func runAutoBackupNow() {
        do {
            _ = try AutoBackupService.runBackup(context: ctx)
            autoBackupRefreshTick += 1
            resultMessage = "Backed up to your folder."
        } catch {
            resultMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func runRestoreFromAutoBackup() {
        do {
            let r = try AutoBackupService.restoreFromAutoBackup(into: ctx, mode: .mergeUpsert)
            resultMessage = "Restored \(r.decks) decks · \(r.cards) cards."
        } catch {
            resultMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func syncReminderState() {
        var comps = DateComponents()
        comps.hour = reminderHour
        comps.minute = reminderMinute
        reminderTime = Calendar.current.date(from: comps) ?? Date()
        Task {
            let status = await NotificationService.currentStatus()
            permissionDenied = (status == .denied)
        }
    }

    private func toggleReminder(_ enable: Bool) async {
        if enable {
            let granted = await NotificationService.requestAuthorization()
            if !granted {
                permissionDenied = true
                reminderEnabled = false
                return
            }
            permissionDenied = false
            reminderEnabled = true
            await NotificationService.scheduleDailyReminder(hour: reminderHour, minute: reminderMinute)
        } else {
            reminderEnabled = false
            await NotificationService.cancelDailyReminder()
        }
    }

    private func rescheduleReminder(for date: Date) async {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let h = comps.hour, let m = comps.minute else { return }
        reminderHour = h
        reminderMinute = m
        if reminderEnabled {
            await NotificationService.scheduleDailyReminder(hour: h, minute: m)
        }
    }
}

@ModelActor
private actor ImportActor {
    func apply(backup: BackupFile, mode: BackupService.MergeMode) throws -> (decks: Int, cards: Int) {
        let r = try BackupService.applyBackup(backup, into: modelContext, mode: mode)
        try modelContext.save()
        return r
    }
}

struct RecycleBinView: View {
    @Environment(\.modelContext) private var ctx
    let onRestore: () -> Void

    @Query(
        filter: #Predicate<Deck> { $0.isDeleted == true },
        sort: \Deck.deletedAt,
        order: .reverse
    ) private var deletedDecks: [Deck]
    
    var body: some View {
        List {
            if deletedDecks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "trash")
                        .font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Recycle bin is empty").font(.headline)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                ForEach(deletedDecks) { deck in
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deck.name).font(.headline)
                            if let date = deck.deletedAt {
                                let daysLeft = 30 - (Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)
                                Text("\(max(0, daysLeft)) days left before permanent deletion")
                                    .font(.caption)
                                    .foregroundStyle(daysLeft < 5 ? .red : .secondary)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            Button {
                                deck.isDeleted = false
                                deck.deletedAt = nil
                                try? ctx.save()
                                onRestore()
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            
                            Button(role: .destructive) {
                                ctx.delete(deck)
                                try? ctx.save()
                            } label: {
                                Label("Delete Permanently", systemImage: "trash")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Recycle Bin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !deletedDecks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Empty Bin", role: .destructive) {
                        for deck in deletedDecks {
                            ctx.delete(deck)
                        }
                        try? ctx.save()
                    }
                }
            }
        }
    }
}
