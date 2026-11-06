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
| `Recap --update-check` | Packaged app only: reads the update feed through Sparkle's Downloader helper and reports what it found, with no window |

Signed build on this Mac (the certificate goes into a throwaway keychain; the login keychain is never touched):

```bash
KC=$(scripts/import-signing-cert.sh <cert.p12> <password-file>)
SIGN_IDENTITY="KevinPlanet9 App Signing" SIGN_KEYCHAIN="$KC" scripts/build-app.sh
security delete-keychain "$KC"
```

## Where things live
| What | Where |
| --- | --- |
| App name, file types for Open With | `Resources/Info.plist` |
| Entitlements | `Resources/Recap.entitlements` (CI allows exactly the sandbox, user-chosen files, app-scoped bookmarks, and Sparkle's two; the build checks that set and that Sparkle's helpers carry no entitlements, on every architecture) |
| In-app updates | `Sources/Recap/Updater.swift` (the only file that imports Sparkle); feed URL and public key in `Resources/Info.plist`; embedding and signing in `scripts/embed-sparkle.sh`; the feed is written by `scripts/make-appcast.sh` |
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
universal app signed with the release certificate, and attaches `Recap.zip` and `appcast.xml`, so
`releases/latest/download/Recap.zip` always gets the newest and the app's update check sees it.

The workflow needs three repository secrets: `CODESIGN_P12_BASE64` and `CODESIGN_P12_PASSWORD` (the
release certificate) and `SPARKLE_ED_PRIVATE_KEY` (signs each update; its public half is `SUPublicEDKey`
in `Resources/Info.plist`, the same key EyeCue uses). Each release gets a new build number
(`BUILD_NUMBER`), which is how Sparkle tells a newer version. Copies built before 0.2.0 have no updater,
so people on 0.1.0 need to download once by hand.

The app itself still has no network entitlement. Only Sparkle's separate Downloader helper fetches the feed
and the update from GitHub, over https; transcripts and recordings never leave the Mac. Sparkle's helpers
(Downloader, Installer, Updater) ship exactly as Sparkle ships them, with no extra entitlements. Don't give
the Downloader its own sandbox: that needs a Sparkle build with an app-specific service id, or it can clash
with other apps that use Sparkle. The Installer runs outside the sandbox because it has to replace the app.


## Check before every release
- `scripts/test.sh` and `scripts/check-real-files.sh` pass.
- A person at the Mac: drag and drop a file, search, click a time to play, export each format, delete.
- Transcribe a real meeting and compare it with what was said, especially names and numbers.
- Keep the privacy promises: no network access for the app (only Sparkle's Downloader helper, for updates), no
  microphone, recordings never copied.
- On the signed app, `Recap --update-check` reads the feed (after the release, it should find no newer
  version), and an older copy offers the new one from Check for Updates.
- An independent review of the code changes (Codex) before a release that changes the engine, saving or exports.
