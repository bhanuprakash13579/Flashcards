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
    @AppStorage("dailyNewCardLimit") private var dailyNewCardLimit = PracticeQueue.defaultDailyNewCardLimit

    @State private var reminderTime = Date()
    @State private var permissionDenied = false
    @State private var autoBackupRefreshTick = 0   // bump to refresh "last backup" label

    var body: some View {
        NavigationStack {
            Form {
                librarySection
                studySection
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
            .alert("Done", isPresented: .constant(resultMessage != nil), presenting: resultMessage) { _ in
                Button("OK") { resultMessage = nil }
            } message: { msg in
                Text(msg)
            }
            .onAppear { syncReminderState() }
        }
    }

    // MARK: - Sections

    private var librarySection: some View {
        Section("Library") {
            LabeledContent("Decks", value: "\(decks.count)")
            LabeledContent("Cards", value: "\(cards.count)")
        }
    }

    private var studySection: some View {
        Section {
            Stepper(value: $dailyNewCardLimit, in: 5...100, step: 5) {
                HStack {
                    Text("New cards per day")
                    Spacer()
                    Text("\(dailyNewCardLimit)").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Study load")
        } footer: {
            Text("Caps how many brand-new cards are introduced each day. Lower = more time on what's already partly learned. The cap resets at midnight.")
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
        do {
            let backup = try BackupService.snapshot(context: ctx)
            let data = try BackupService.encode(backup)
            exportDocument = BackupDocument(data: data)
            exportFilename = "flashcards-\(stampedFilename()).json"
            exporting = true
        } catch {
            resultMessage = "Could not build backup: \(error.localizedDescription)"
        }
    }

    private func stampedFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: Date())
    }

    private func runImport(_ mode: BackupService.MergeMode) {
        guard let url = pendingImportURL else { return }
        defer { pendingImportURL = nil }
        do {
            let r = try BackupService.restore(from: url, into: ctx, mode: mode)
            resultMessage = "Imported \(r.decks) decks · \(r.cards) cards."
        } catch {
            resultMessage = "Import failed: \(error.localizedDescription)"
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
            try AutoBackupService.runBackup(context: ctx)
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
