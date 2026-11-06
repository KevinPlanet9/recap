# Build log

## 2026-11-06: version 0.1.0

First version, built from the plan "Transcription App Handoff".

- On-device transcription with Apple's SpeechAnalyzer and SpeechTranscriber (macOS 26 or later). The file
  is read with `AVAssetReaderAudioMixOutput` over every sound track, in the engine's format, through an
  AsyncSequence that hands the engine one buffer at a time.
- Lines end at a sentence end, a pause of 1.2 seconds, 20 seconds or 240 characters.
- Screens: start (drop zone, Choose a File, language picker), working (progress, lines as they arrive,
  Cancel, how many are waiting, Mac kept awake), transcript (search, click a time to play, highlighted
  playing line, Copy All, Export to txt, md, srt, vtt and json, Delete with a confirmation), and a sidebar
  of saved transcripts. Drag and drop, Open With and the file picker all work. Recap's own dialogs, and a
  question before quitting if it would lose work.
- Saving never loses a finished transcript: if it fails, the transcript stays open with Try Saving Again
  and Export. A saved-transcripts folder that can't be read shows an error, never an empty list. Damaged
  files are counted and kept. Times are clamped before any Int conversion.
- App Sandbox with only user-chosen files and app-scoped bookmarks. CI fails on networking, microphone or
  camera APIs or any other entitlement, and the build checks the signed entitlements.
- 25 unit tests (times, line building, search, exports, saved and damaged files).
- An independent code review (Codex) before release found one high and five medium problems, all fixed:
  cancelling a job and starting another right away could let the old job clear the new one (each job now
  has its own id); a part of the sound that failed to convert was skipped silently (it now fails the job);
  a transcript that failed to save could become unreachable if the saved list also failed to load (it now
  always shows); a saved file claiming another file's id could make Delete remove the wrong file, and a
  huge file could be read into memory at launch (both are now set aside as damaged); Markdown exports
  didn't escape the title and file name (now they do). Two low ones are fixed too: subtitle markup is
  escaped, and a moved recording's bookmark is refreshed. Four new tests cover the store and export fixes.

Checked on an M5 MacBook Pro running macOS 27.0.1, from the command line (no window):

| Check | Result |
| --- | --- |
| Spoken script (`say`), 15 s | every word heard, 7 lines, 0.4 s |
| 4 hour file | 2 min 7 s, 6,606 lines, peak memory 15 MB |
| 60 s of silence | "No speech found", nothing saved |
| Video with no sound | "This file has no sound to transcribe." |
| Cut-off file, fake file | plain-English "couldn't read this file" message |
| Silent first track, speech on the second | every line heard |
| Cancel after 5 s of the 4 hour file | stopped within 0.05 s |
| Signed app launch check | sandbox on, store in the container, engine available, 45 languages |

The screens were drawn offscreen with sample data and look as designed. Not yet checked by a person at the
Mac: drag and drop into the real window, playback, the save panel for exports, and a real meeting's accuracy.
