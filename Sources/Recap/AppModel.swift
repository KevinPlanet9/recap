import AppKit
import Foundation
import RecapCore
import UniformTypeIdentifiers

/// The app's state. A small ObservableObject held with StateObject (not the @State macro, which
/// fails to build with only the Command Line Tools installed).
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Screen: Equatable {
        case start
        case working
        case transcript(UUID)
    }

    struct Job {
        var id = UUID()
        var url: URL
        var title: String
        var fraction: Double = 0
        var lines: [Line] = []
        var pendingText = ""
        var preparing = true
    }

    enum Dialog: Identifiable {
        case message(title: String, text: String)
        case confirmDelete(Transcript)
        case confirmQuit

        var id: String {
            switch self {
            case .message(let title, let text): return "m:\(title):\(text)"
            case .confirmDelete(let t): return "d:\(t.id)"
            case .confirmQuit: return "q"
            }
        }
    }

    // Saved transcripts
    @Published private(set) var saved: [Transcript] = []
    @Published private(set) var loadError: String?
    @Published private(set) var damagedCount = 0
    @Published private(set) var loaded = false

    // A finished transcript that could not be saved. It stays open until it is saved or exported.
    @Published private(set) var unsaved: Transcript?
    @Published private(set) var saveError: String?

    // Work in progress
    @Published var screen: Screen = .start
    @Published private(set) var job: Job?
    @Published private(set) var waiting: [URL] = []

    // Language
    @Published private(set) var locales: [Locale] = []
    @Published var localeID: String = ""

    @Published private(set) var dialog: Dialog?
    private var queuedDialogs: [Dialog] = []

    private var store: TranscriptStore?
    private var task: Task<Void, Never>?
    private var activity: NSObjectProtocol?

    init() {}

    // MARK: Loading

    func start() {
        guard !loaded else { return }
        loaded = true
        reload()
        Task {
            let all = await TranscriptionEngine.supportedLocales()
            let preferred = await TranscriptionEngine.defaultLocale()
            locales = all
            if localeID.isEmpty {
                localeID = all.first(where: { $0.identifier == preferred.identifier })?.identifier
                    ?? all.first?.identifier ?? preferred.identifier
            }
        }
    }

    func reload() {
        do {
            let store = try self.store ?? TranscriptStore(folder: TranscriptStore.defaultFolder())
            self.store = store
            let result = try store.loadAll()
            saved = result.transcripts
            damagedCount = result.damaged.count
            loadError = nil
        } catch {
            // Never show an empty list for a read that failed.
            loadError = error.localizedDescription
        }
    }

    // MARK: Adding files

    static let acceptedTypes: [UTType] = [.audio, .movie, .audiovisualContent]

    func add(_ urls: [URL]) {
        var rejected: [String] = []
        for url in urls {
            guard url.isFileURL else { rejected.append(url.absoluteString); continue }
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            guard let type, Self.acceptedTypes.contains(where: { type.conforms(to: $0) }) else {
                rejected.append(url.lastPathComponent)
                continue
            }
            waiting.append(url)
        }
        if !rejected.isEmpty {
            present(.message(title: "Recap reads audio and video files",
                              text: "These weren't added: \(rejected.joined(separator: ", "))."))
        }
        startNextIfIdle()
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.acceptedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose recordings to transcribe"
        panel.prompt = "Transcribe"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    // MARK: The job

    var locale: Locale { Locale(identifier: localeID.isEmpty ? "en_US" : localeID) }

    private func startNextIfIdle() {
        guard job == nil, unsaved == nil, !waiting.isEmpty else { return }
        let url = waiting.removeFirst()
        let newJob = Job(url: url, title: transcriptTitle(forFileNamed: url.lastPathComponent))
        let jobID = newJob.id
        job = newJob
        screen = .working
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Transcribing a recording")
        let locale = self.locale
        task = Task { [weak self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                 includingResourceValuesForKeys: nil, relativeTo: nil)
            do {
                let output = try await TranscriptionEngine.transcribe(url: url, locale: locale) { progress in
                    Task { @MainActor in self?.apply(progress, to: jobID) }
                }
                self?.finished(jobID, url: url, bookmark: bookmark, locale: locale, output: output)
            } catch is CancellationError {
                // cancel() already ended this job; a late result must not touch the next one.
                if self?.job?.id == jobID { self?.endJob() }
            } catch {
                self?.failed(jobID, url: url, error: error)
            }
        }
    }

    private func apply(_ progress: TranscriptionEngine.Progress, to jobID: UUID) {
        guard job?.id == jobID else { return }
        job?.preparing = false
        job?.fraction = max(job?.fraction ?? 0, progress.fraction)
        job?.lines.append(contentsOf: progress.newLines)
        job?.pendingText = progress.pendingText
    }

    func cancel() {
        waiting.removeAll()
        task?.cancel()
        endJob()
    }

    private func endJob() {
        task = nil
        job = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        if screen == .working { screen = .start }
        startNextIfIdle()
    }

    private func finished(_ jobID: UUID, url: URL, bookmark: Data?, locale: Locale, output: TranscriptionEngine.Output) {
        guard job?.id == jobID else { return }  // cancelled meanwhile
        if output.lines.isEmpty {
            present(.message(title: "No speech found",
                              text: "Recap didn't hear any speech in \(url.lastPathComponent). Nothing was saved."))
            endJob()
            return
        }
        let transcript = Transcript(title: transcriptTitle(forFileNamed: url.lastPathComponent),
                                    sourceName: url.lastPathComponent, bookmark: bookmark,
                                    locale: locale.identifier, duration: output.duration, lines: output.lines)
        task = nil
        job = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        save(transcript)
        screen = .transcript(transcript.id)
        startNextIfIdle()
    }

    private func failed(_ jobID: UUID, url: URL, error: Error) {
        guard job?.id == jobID else { return }
        present(.message(title: "Couldn't transcribe \(url.lastPathComponent)", text: error.localizedDescription))
        endJob()
    }

    // MARK: Saving

    /// Never loses a finished transcript: if saving fails it stays open with Try Saving Again and Export.
    private func save(_ transcript: Transcript) {
        do {
            guard let store else { throw TranscriptStore.StoreError.notSaved(loadError ?? "The save folder isn't available.") }
            try store.save(transcript)
            unsaved = nil
            saveError = nil
            saved.removeAll { $0.id == transcript.id }
            saved.insert(transcript, at: 0)
        } catch {
            unsaved = transcript
            saveError = error.localizedDescription
        }
    }

    func trySavingAgain() {
        if store == nil { reload() }
        guard let unsaved else { return }
        save(unsaved)
        if self.unsaved == nil { startNextIfIdle() }
    }

    func transcript(_ id: UUID) -> Transcript? {
        if let unsaved, unsaved.id == id { return unsaved }
        return saved.first { $0.id == id }
    }

    /// Saves a refreshed bookmark after the recording moved. Quietly does nothing if saving fails;
    /// the old bookmark still works until the next move.
    func updateBookmark(_ id: UUID, _ bookmark: Data) {
        guard var transcript = saved.first(where: { $0.id == id }) else { return }
        transcript.bookmark = bookmark
        guard (try? store?.save(transcript)) != nil else { return }
        if let i = saved.firstIndex(where: { $0.id == id }) { saved[i] = transcript }
    }

    // MARK: Delete, copy, export

    func askToDelete(_ transcript: Transcript) { present(.confirmDelete(transcript)) }

    func delete(_ transcript: Transcript) {
        do {
            try store?.delete(transcript.id)
            saved.removeAll { $0.id == transcript.id }
            if unsaved?.id == transcript.id { unsaved = nil; saveError = nil; startNextIfIdle() }
            if screen == .transcript(transcript.id) { screen = .start }
        } catch {
            present(.message(title: "Couldn't delete the transcript", text: error.localizedDescription))
        }
    }

    func copyAll(_ transcript: Transcript) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.plainText, forType: .string)
    }

    func export(_ transcript: Transcript, as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = transcript.title + "." + format.fileExtension
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        panel.message = "Export the transcript as \(format.label)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Exporter.render(transcript, as: format).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            present(.message(title: "Couldn't export", text: error.localizedDescription))
        }
    }

    // MARK: Sample data for --render-screens

    func setForScreens(saved: [Transcript], locales: [Locale]) {
        loaded = true
        self.saved = saved
        self.locales = locales
        localeID = locales.first?.identifier ?? "en_US"
    }

    func seedJobForScreens(title: String, fraction: Double, lines: [Line], waiting count: Int) {
        job = Job(url: URL(fileURLWithPath: "/\(title).m4a"), title: title, fraction: fraction, lines: lines,
                  pendingText: "", preparing: false)
        waiting = (0..<count).map { URL(fileURLWithPath: "/waiting-\($0).m4a") }
        screen = .working
    }

    // MARK: Dialogs, one at a time

    func present(_ next: Dialog) {
        if dialog == nil { dialog = next } else { queuedDialogs.append(next) }
    }

    func dismissDialog() {
        dialog = queuedDialogs.isEmpty ? nil : queuedDialogs.removeFirst()
    }

    // MARK: Quitting

    /// True when quitting now would lose work: a transcription running or waiting, or a transcript not saved.
    var workAtRisk: Bool { job != nil || !waiting.isEmpty || unsaved != nil }

    func askToQuit() {
        present(.confirmQuit)
    }

    var quitWarning: String {
        if unsaved != nil { return "A finished transcript hasn't been saved. Export it or use Try Saving Again first." }
        let count = (job == nil ? 0 : 1) + waiting.count
        return count == 1 ? "A recording is still being transcribed. Quitting stops it." : "\(count) recordings are still being transcribed or waiting. Quitting stops them."
    }

    func cancelForQuit() {
        waiting.removeAll()
        task?.cancel()
    }

    func quitAnyway() {
        cancelForQuit()
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    func stayOpen() {
        NSApp.reply(toApplicationShouldTerminate: false)
    }

}
