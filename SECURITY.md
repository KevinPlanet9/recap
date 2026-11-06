# Security and privacy

Recap reads recordings that may hold personal or sensitive company information, so its controls are
about keeping that audio and the transcripts on the Mac. Each control below names where it is
implemented, so it can be checked.

## Controls in place

| Control | Where |
| --- | --- |
| App Sandbox on, with no network entitlement: macOS blocks all network access | `Resources/Recap.entitlements` |
| Only user-chosen files (read and write, for exports) and app-scoped bookmarks are granted; no microphone or camera | `Resources/Recap.entitlements` |
| CI fails if a networking, microphone or camera API appears in the code, or if the entitlements are anything but those three | `scripts/check-no-network.sh`, `.github/workflows/ci.yml` |
| The build checks the entitlements actually signed into the app, not just the file | `scripts/build-app.sh` |
| Speech recognition runs on the Mac with Apple's SpeechAnalyzer and SpeechTranscriber | `Sources/Recap/TranscriptionEngine.swift` |
| Recordings are read in place and never copied; audio goes from the file to the engine a buffer at a time | `Sources/Recap/AudioFileSequence.swift` |
| Only file URLs of audio and video types are accepted | `AppModel.add(_:)` |
| Transcripts are JSON files in the app's sandbox container, and nowhere else unless you export one | `Sources/RecapCore/TranscriptStore.swift` |
| The security bookmark to the recording is never included in exports | `Exporter.JSONExport` |
| Damaged saved files are counted and kept, never deleted; times are clamped so a bad file can't crash the app | `TranscriptStore.loadAll()`, `Transcript.sanitized()`, `TimeFormat.clamp` |
| Subtitle exports can't be broken by "-->" or blank lines in the text | `Exporter.subtitleText` |
| Hardened runtime on the app signature | `scripts/build-app.sh` |
| Secret scan of the full history on every push (pinned, checksum-verified gitleaks) | `.github/workflows/secret-scan.yml` |
| GitHub Actions pinned to commit hashes, updated monthly by Dependabot in one grouped pull request | `.github/workflows/`, `.github/dependabot.yml` |
| No accounts, analytics, crash reporting or telemetry | the whole of `Sources/` |

## What is stored, and for how long

- **Transcripts:** in `~/Library/Containers/local.recap.Recap/Data/Library/Application Support/Recap/Transcripts`,
  one JSON file each, with the text, the times, the recording's file name and a bookmark to it.
  They are kept until you delete them in the app. Deleting removes the JSON file only.
- **Recordings:** never stored by Recap. It reads them where they are.
- **The speech model:** downloaded and managed by macOS, shared with other apps that use it.

## Who can see transcripts

Anyone who can sign in to the Mac's user account can open the app and read them. Use FileVault and a
screen lock. Exports are ordinary files: share them as carefully as the recording.

## Consent

Recap doesn't record anything itself. Get consent before recording people, and follow your company's
rules for how long recordings and transcripts are kept. The start screen says so.

## Limits

The first use of a language needs macOS to download its speech model; that download is made by macOS,
not by Recap. Without a paid Apple Developer ID, a downloaded copy shows a macOS warning the first time
it opens (see the README).

## Reporting a problem

Open an issue on the repository, or contact the owner directly for anything sensitive.
