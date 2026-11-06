import Foundation
import Testing
@testable import RecapCore

// MARK: Times

@Test func timesFormatForScreenAndSubtitles() {
    #expect(TimeFormat.display(0) == "0:00")
    #expect(TimeFormat.display(65.9) == "1:05")
    #expect(TimeFormat.display(3725) == "1:02:05")
    #expect(TimeFormat.srt(3725.25) == "01:02:05,250")
    #expect(TimeFormat.vtt(3725.25) == "01:02:05.250")
}

@Test func timesClampBeforeConverting() {
    #expect(TimeFormat.clamp(-5) == 0)
    #expect(TimeFormat.clamp(.nan) == 0)
    #expect(TimeFormat.clamp(.infinity) == 0)
    #expect(TimeFormat.clamp(1e300) == TimeFormat.maximumSeconds)
    // Would trap if converted to Int without clamping.
    #expect(TimeFormat.display(1e300) == "99:59:59")
    #expect(TimeFormat.srt(Double.greatestFiniteMagnitude) == "99:59:59,999")
}

// MARK: Line building

private func words(_ spec: [(String, Double)]) -> [Word] {
    spec.map { Word(text: $0.0, start: $0.1, end: $0.1 + 0.3) }
}

@Test func linesEndAtSentenceEnds() {
    var b = LineBuilder()
    b.add(words([("Hello", 0), ("there.", 0.4), ("How", 0.8), ("are", 1.1), ("you?", 1.4), ("Fine", 1.8)]))
    b.finish()
    #expect(b.lines.map(\.text) == ["Hello there.", "How are you?", "Fine"])
    #expect(b.lines.map(\.id) == [0, 1, 2])
    #expect(b.lines[1].start == 0.8)
}

@Test func linesEndAtPauses() {
    var b = LineBuilder()
    b.add(words([("one", 0), ("two", 0.4), ("three", 2.5)]))  // 1.8 s gap after "two"
    b.finish()
    #expect(b.lines.map(\.text) == ["one two", "three"])
}

@Test func linesEndAtTwentySeconds() {
    var b = LineBuilder()
    b.add((0..<30).map { Word(text: "w\($0)", start: Double($0), end: Double($0) + 0.9) })
    b.finish()
    #expect(b.lines.count == 2)
    #expect(b.lines.allSatisfy { $0.end - $0.start <= 20 })
}

@Test func linesEndAt240Characters() {
    var b = LineBuilder()
    let long = String(repeating: "x", count: 50)
    b.add((0..<10).map { Word(text: long, start: Double($0) * 0.5, end: Double($0) * 0.5 + 0.4) })
    b.finish()
    #expect(b.lines.allSatisfy { $0.text.count <= 240 })
    #expect(b.lines.count == 3)
}

@Test func punctuationJoinsWithoutSpaces() {
    var b = LineBuilder()
    b.add(words([("Yes", 0), (",", 0.2), ("we", 0.3), ("did", 0.5), (".", 0.7)]))
    #expect(b.lines.map(\.text) == ["Yes, we did."])
}

@Test func emptyWordsAreSkippedAndBadTimesClamped() {
    var b = LineBuilder()
    b.add([Word(text: "  ", start: 0, end: 1), Word(text: "ok", start: -3, end: .nan)])
    b.finish()
    #expect(b.lines == [Line(id: 0, start: 0, end: 0, text: "ok")])
}

// MARK: Search

private let sample: [Line] = [
    Line(id: 0, start: 0, end: 2, text: "Welcome to the café meeting."),
    Line(id: 1, start: 2, end: 4, text: "Budget is 4.2 million."),
    Line(id: 2, start: 4, end: 6, text: "We\u{2019}ll review the budget Friday."),
]

@Test func searchIgnoresCaseAndAccents() {
    #expect(TranscriptSearch.matches("CAFE", in: sample) == [0])
    #expect(TranscriptSearch.matches("budget", in: sample) == [1, 2])
    #expect(TranscriptSearch.matches("budget friday", in: sample) == [2])
    #expect(TranscriptSearch.matches("we'll", in: sample) == [2])
    #expect(TranscriptSearch.matches("   ", in: sample) == [0, 1, 2])
    #expect(TranscriptSearch.matches("nothing", in: sample).isEmpty)
}

@Test func playingLineLookup() {
    let t = Transcript(title: "t", sourceName: "t.m4a", bookmark: nil, locale: "en_US", duration: 6, lines: sample)
    #expect(t.lineIndex(at: -1) == nil)
    #expect(t.lineIndex(at: 0) == 0)
    #expect(t.lineIndex(at: 3.9) == 1)
    #expect(t.lineIndex(at: 100) == 2)
    #expect(t.lineIndex(at: .nan) == nil)
}

// MARK: Exports

private func transcript(_ lines: [Line] = sample) -> Transcript {
    Transcript(title: "Board meeting", sourceName: "Board meeting.m4a", bookmark: nil, locale: "en_US",
               createdAt: Date(timeIntervalSince1970: 1_800_000_000), duration: 6, lines: lines)
}

@Test func exportsText() throws {
    let txt = try Exporter.render(transcript(), as: .txt)
    #expect(txt.hasPrefix("[0:00] Welcome to the café meeting.\n[0:02] Budget is 4.2 million.\n"))
}

@Test func exportsSubRip() throws {
    let srt = try Exporter.render(transcript(), as: .srt)
    #expect(srt.hasPrefix("1\n00:00:00,000 --> 00:00:02,000\nWelcome to the café meeting.\n\n2\n00:00:02,000"))
}

@Test func exportsWebVTT() throws {
    let vtt = try Exporter.render(transcript(), as: .vtt)
    #expect(vtt.hasPrefix("WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nWelcome"))
}

@Test func subtitleTextCannotBreakTheFile() throws {
    let bad = [Line(id: 0, start: 0, end: 1, text: "a --> b\n\nc ---> d"), Line(id: 1, start: 1, end: 2, text: "\n")]
    let srt = try Exporter.render(transcript(bad), as: .srt)
    #expect(!srt.contains("a -->"))
    #expect(srt.contains("a -\u{203A} b c -\u{203A} d"))  // arrows defused, then ">" made harmless
    #expect(srt.components(separatedBy: "-->").count - 1 == 2)  // only the two timing lines
    let vtt = try Exporter.render(transcript(bad), as: .vtt)
    #expect(!vtt.contains("\n\n\n"))
    #expect(vtt.contains("\n...\n"))
}

@Test func exportsMarkdownEscaped() throws {
    let md = try Exporter.render(transcript([Line(id: 0, start: 61, end: 62, text: "# not a *heading*")]), as: .md)
    #expect(md.hasPrefix("# Board meeting\n"))
    #expect(md.contains("**1:01** \\# not a \\*heading\\*"))
}

@Test func exportsJSON() throws {
    let json = try Exporter.render(transcript(), as: .json)
    let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    #expect(obj["title"] as? String == "Board meeting")
    #expect((obj["lines"] as? [[String: Any]])?.count == 3)
    #expect(obj["bookmark"] == nil)  // the bookmark stays private to the app
}

// MARK: Saved transcripts

private func tempFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("recap-tests-\(UUID().uuidString)", isDirectory: true)
}

@Test func savesLoadsAndDeletes() throws {
    let store = TranscriptStore(folder: tempFolder())
    defer { try? FileManager.default.removeItem(at: store.folder) }
    #expect(try store.loadAll().transcripts.isEmpty)  // no folder yet is fine
    let a = transcript()
    var b = transcript(); b.id = UUID(); b.createdAt = a.createdAt.addingTimeInterval(60)
    try store.save(a)
    try store.save(b)
    let loaded = try store.loadAll()
    #expect(loaded.transcripts.map(\.id) == [b.id, a.id])  // newest first
    #expect(loaded.transcripts[1] == a)
    try store.delete(a.id)
    #expect(try store.loadAll().transcripts.map(\.id) == [b.id])
}

@Test func damagedFilesAreCountedAndKept() throws {
    let store = TranscriptStore(folder: tempFolder())
    defer { try? FileManager.default.removeItem(at: store.folder) }
    try store.save(transcript())
    let bad = store.folder.appendingPathComponent("broken.json")
    try Data("{ not json".utf8).write(to: bad)
    let result = try store.loadAll()
    #expect(result.transcripts.count == 1)
    #expect(result.damaged.map(\.lastPathComponent) == ["broken.json"])
    #expect(FileManager.default.fileExists(atPath: bad.path))
}

@Test func hugeTimesInASavedFileAreClampedNotCrashed() throws {
    let store = TranscriptStore(folder: tempFolder())
    defer { try? FileManager.default.removeItem(at: store.folder) }
    try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
    let id = UUID()
    let json = """
    {"version":1,"id":"\(id.uuidString)","title":"x","sourceName":"x.m4a","locale":"en_US",
     "createdAt":"2026-11-06T12:00:00Z","duration":1e308,
     "lines":[{"id":7,"start":1e300,"end":-4,"text":"hi"},{"id":7,"start":"nan","end":"inf","text":"there"}]}
    """
    try Data(json.utf8).write(to: store.url(for: id))
    let t = try #require(try store.loadAll().transcripts.first)
    #expect(t.duration == TimeFormat.maximumSeconds)
    #expect(t.lines.map(\.id) == [0, 1])
    #expect(t.lines[0].start == TimeFormat.maximumSeconds && t.lines[0].end == TimeFormat.maximumSeconds)
    #expect(t.lines[1].start == 0 && t.lines[1].end == 0)
    _ = TimeFormat.display(t.lines[0].start)
}

@Test func unreadableFolderIsAnErrorNotAnEmptyList() throws {
    let file = tempFolder()
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(throws: TranscriptStore.StoreError.self) { try TranscriptStore(folder: file).loadAll() }
}

@Test func filesWhoseIdDoesNotMatchTheirNameAreSetAside() throws {
    let store = TranscriptStore(folder: tempFolder())
    defer { try? FileManager.default.removeItem(at: store.folder) }
    let a = transcript()
    var b = transcript(); b.id = UUID()
    try store.save(a)
    try store.save(b)
    // Copy B's contents into a file named for another id: it claims B's identity.
    let impostor = store.folder.appendingPathComponent(UUID().uuidString + ".json")
    try FileManager.default.copyItem(at: store.url(for: b.id), to: impostor)
    let result = try store.loadAll()
    #expect(Set(result.transcripts.map(\.id)) == [a.id, b.id])
    #expect(result.damaged.map(\.lastPathComponent) == [impostor.lastPathComponent])
}

@Test func oversizedFilesAreSetAsideUnread() throws {
    let folder = tempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try TranscriptStore(folder: folder).save(transcript())
    let big = folder.appendingPathComponent(UUID().uuidString + ".json")
    try Data(count: 5000).write(to: big)
    let result = try TranscriptStore(folder: folder, maximumFileBytes: 4000).loadAll()
    #expect(result.transcripts.count == 1)
    #expect(result.damaged.map(\.lastPathComponent) == [big.lastPathComponent])
}

@Test func markdownMetadataCannotFormLinksOrImages() throws {
    var t = transcript([Line(id: 0, start: 0, end: 1, text: "see [here](https://x.invalid) <b>")])
    t.title = "![pixel](https://x.invalid/p.png)"
    t.sourceName = "<img src=x>.m4a"
    let md = try Exporter.render(t, as: .md)
    // Every bracket and angle bracket is escaped, so nothing renders as a link, image or HTML.
    #expect(md.contains("\\!\\[pixel\\](https://x.invalid/p.png)") || md.contains("!\\[pixel\\](https://x.invalid/p.png)"))
    #expect(md.contains("\\<img src=x\\>"))
    #expect(md.contains("\\[here\\](https://x.invalid)"))
    #expect(md.contains("\\<b\\>"))
    #expect(!md.contains("[pixel]("))
    #expect(!md.contains("[here]("))
}

@Test func subtitleMarkupShowsAsTyped() throws {
    let t = transcript([Line(id: 0, start: 0, end: 1, text: "<b>bold</b> & <00:00:05.000>")])
    let vtt = try Exporter.render(t, as: .vtt)
    #expect(vtt.contains("&lt;b&gt;bold&lt;/b&gt; &amp; &lt;00:00:05.000&gt;"))
    let srt = try Exporter.render(t, as: .srt)
    #expect(!srt.contains("<b>"))
}

@Test func titlesComeFromFileNames() {
    #expect(transcriptTitle(forFileNamed: "Board meeting.m4a") == "Board meeting")
    #expect(transcriptTitle(forFileNamed: ".m4a") == "Untitled recording")
    #expect(transcriptTitle(forFileNamed: "Q3 review v1.2 final.mov") == "Q3 review v1.2 final")
    #expect(transcriptTitle(forFileNamed: "No extension") == "No extension")
}
