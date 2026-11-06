# Maintaining Recap

## Build and test
You need macOS 26 or later and the Xcode Command Line Tools (or Xcode).

```bash
scripts/test.sh                  # unit tests, the no-network check, the smoke test (no window)
scripts/check-real-files.sh      # the speech engine on real files: spoken script, silence, damaged, fake, two tracks, Cancel
LONG=1 scripts/check-real-files.sh   # adds a 4 hour file with time and memory
scripts/build-app.sh --install   # builds the signed app and moves it to ~/Applications
```

`check-real-files.sh` uses `say` for speech and ffmpeg (on PATH, or `FFMPEG=/path/to/ffmpeg`) for the
silence, no-sound, two-track, Cancel and 4 hour cases. It runs on a Mac, not in CI, because it needs the
language model.

The command line modes never open a window:

| Mode | What it does |
| --- | --- |
| `Recap --transcribe <file> [--locale en_US] [--format txt\|md\|srt\|vtt\|json] [--cancel-after <s>]` | Transcribes to standard output. Exit 0 done, 1 error, 3 no speech, 4 cancelled |
| `Recap --smoke-test` | Exercises the core with no engine |
| `Recap --launch-check` | Starts as the signed, sandboxed app would, reads its folder, checks the engine, quits |
| `Recap --render-screens <folder>` | Draws each screen with sample data to PNGs (the README pictures), offscreen |

## Where things live
| What | Where |
| --- | --- |
| App name, file types for Open With | `Resources/Info.plist` |
| Entitlements | `Resources/Recap.entitlements` (CI allows exactly three) |
| App icon | `Resources/AppIcon.png`, drawn by `swift scripts/make-icon.swift Resources/AppIcon.png` |
| Colors and fonts | `Theme` in `Sources/Recap/Theme.swift` |
| Speech engine | `Sources/Recap/TranscriptionEngine.swift`, file reading in `AudioFileSequence.swift` |
| Line rules (sentence end, 1.2 s pause, 20 s, 240 characters) | `LineBuilder` in `Sources/RecapCore/LineBuilder.swift` |
| Exports | `Sources/RecapCore/Exporter.swift` |
| Saved transcripts | `Sources/RecapCore/TranscriptStore.swift` |
| Screens | `Sources/Recap/ContentView.swift`; state in `AppModel.swift` |
| README pictures | `Recap --render-screens docs` |

SwiftUI state uses `@StateObject` with small `ObservableObject` classes, not the `@State` macro, which
fails to build with only the Command Line Tools installed.

## Publish a download
Set the version in `scripts/build-app.sh` and `scripts/package-release.sh`, add a dated entry to
`docs/BUILD-LOG.md`, then push a tag such as `v0.2.0`. `.github/workflows/release.yml` tests, builds a
universal app and attaches `Recap.zip`, so `releases/latest/download/Recap.zip` always gets the newest.

While the repository is private, that link works only for people signed in to GitHub with access to it.

## Check before every release
- `scripts/test.sh` and `scripts/check-real-files.sh` pass.
- A person at the Mac: drag and drop a file, search, click a time to play, export each format, delete.
- Transcribe a real meeting and compare it with what was said, especially names and numbers.
- Keep the privacy promises: no network access, no microphone, recordings never copied.
- An independent review of the code changes (Codex) before a release that changes the engine, saving or exports.
