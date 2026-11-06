import AppKit
import SwiftUI

struct RecapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @StateObject private var player = Player()

    var body: some Scene {
        Window("Recap", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(player)
                .frame(minWidth: 820, minHeight: 540)
                .preferredColorScheme(.dark)
                .onAppear { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Transcribe a Recording...") { model.chooseFiles() }
                    .keyboardShortcut("o")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
