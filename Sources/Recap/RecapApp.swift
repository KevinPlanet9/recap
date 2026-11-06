import AppKit
import SwiftUI

struct RecapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @StateObject private var player = Player()
    @StateObject private var updater = Updater.shared

    var body: some Scene {
        Window("Recap", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(player)
                .frame(minWidth: 820, minHeight: 540)
                .preferredColorScheme(.dark)
                .onAppear {
                    model.start()
                    player.onBookmarkRefresh = { id, data in model.updateBookmark(id, data) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                UpdateCommands(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Transcribe a Recording...") { model.chooseFiles() }
                    .keyboardShortcut("o")
            }
        }
    }
}

/// App menu, after About Recap: Check for Updates... and Check for Updates Automatically.
/// Shown only in the packaged app, where Sparkle is running.
struct UpdateCommands: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if updater.isAvailable {
            Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecks)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// In-app updates start here, with a check on launch when automatic checks are on.
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Updater.shared.start(checkNow: true) }
    }

    /// Open With, and files dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { AppModel.shared.add(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !AppModel.shared.workAtRisk }
    }

    /// Asks before quitting if it would lose work.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard AppModel.shared.workAtRisk else { return .terminateNow }
            NSApp.activate()
            if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
                window.makeKeyAndOrderFront(nil)
                AppModel.shared.askToQuit()  // Recap's own dialog in the window
                return .terminateLater
            }
            // No window to show the dialog in: fall back to a standard alert so quitting never hangs.
            let alert = NSAlert()
            alert.messageText = "Quit and lose work?"
            alert.informativeText = AppModel.shared.quitWarning
            alert.addButton(withTitle: "Keep Recap Open")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertSecondButtonReturn {
                AppModel.shared.cancelForQuit()
                return .terminateNow
            }
            return .terminateCancel
        }
    }
}
