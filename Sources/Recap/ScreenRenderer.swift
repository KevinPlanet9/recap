import AppKit
import RecapCore
import SwiftUI

/// `Recap --render-screens <folder>` draws each screen to a PNG with sample data, for the README
/// and for checking layout. The window it draws into is never put on screen.
@MainActor
enum ScreenRenderer {
    static func run(folder: String) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)  // no Dock icon, no menu bar, nothing on screen
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let sample = sampleTranscript()
        let older = Transcript(title: "Safety stand-down", sourceName: "Safety stand-down.m4a", bookmark: nil,
                               locale: "en_US", createdAt: Date(timeIntervalSinceNow: -86400 * 3), duration: 2710, lines: sample.lines)

        let shots: [(String, (AppModel) -> Void)] = [
            ("start", { m in m.seedForScreens(saved: [sample, older], locales: ["en_US", "en_GB", "es_US"]) }),
            ("working", { m in
                m.seedForScreens(saved: [older], locales: ["en_US"])
                m.seedJobForScreens(title: "Weekly operations review", fraction: 0.42, lines: Array(sample.lines.prefix(5)), waiting: 2)
            }),
            ("transcript", { m in
                m.seedForScreens(saved: [sample, older], locales: ["en_US"])
                m.screen = .transcript(sample.id)
            }),
            ("delete", { m in
                m.seedForScreens(saved: [sample, older], locales: ["en_US"])
                m.screen = .transcript(sample.id)
                m.askToDelete(sample)
            }),
        ]
        for (name, setup) in shots {
            let model = AppModel()
            setup(model)
            let view = ContentView()
                .environmentObject(model)
                .environmentObject(Player())
                .frame(width: 1100, height: 700)
                .preferredColorScheme(.dark)
            guard let png = snapshot(view, size: NSSize(width: 1100, height: 700)) else {
                FileHandle.standardError.write(Data("Couldn't draw \(name)\n".utf8))
                return 1
            }
            do { try png.write(to: out.appendingPathComponent("\(name).png")) } catch { return 1 }
            print("Wrote \(name).png")
        }
        return 0
    }

    private static func snapshot<V: View>(_ view: V, size: NSSize) -> Data? {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        // Offscreen, borderless, and never ordered front: nothing appears on the screen.
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.contentView = nil
        return rep.representation(using: .png, properties: [:])
    }

    static func sampleTranscript() -> Transcript {
        let texts = [
            "Good morning, everyone. This is the weekly operations review.",
            "We have three items today.",
            "First, the new scheduling system goes live on Tuesday.",
            "Training sessions are on the calendar for Monday afternoon.",
            "Second, the budget for the quarter is on track.",
            "We came in about two percent under on travel.",
            "Third, please finish your training by Friday.",
            "If anything is unclear, send questions to the help desk.",
            "Any questions before we wrap up?",
            "Thanks, everyone. See you next week.",
        ]
        var t = 0.0
        let lines = texts.enumerated().map { i, text -> Line in
            defer { t += Double(text.count) / 14 + 1.1 }
            return Line(id: i, start: t, end: t + Double(text.count) / 14, text: text)
        }
        return Transcript(title: "Weekly operations review", sourceName: "Weekly operations review.m4a", bookmark: nil,
                          locale: "en_US", duration: t, lines: lines)
    }
}

extension AppModel {
    /// Sample data for `--render-screens` only. Never touches the saved transcripts folder.
    func seedForScreens(saved: [Transcript], locales: [String]) {
        setForScreens(saved: saved, locales: locales.map { Locale(identifier: $0) })
    }
}
