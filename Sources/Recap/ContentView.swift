import RecapCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var drop = DropState()

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 250)
            Rectangle().fill(Theme.line).frame(width: 1)
            ZStack {
                Theme.ground
                switch model.screen {
                case .start: StartView(dropTargeted: drop.targeted)
                case .working: WorkingView()
                case .transcript(let id):
                    if let t = model.transcript(id) { TranscriptView(transcript: t).id(t.id) } else { StartView(dropTargeted: drop.targeted) }
                }
            }
        }
        .background(Theme.ground)
        .foregroundColor(Theme.paper)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return !urls.isEmpty
        } isTargeted: { drop.targeted = $0 }
        .overlay { if let dialog = model.dialog { DialogView(dialog: dialog) } }
    }
}

// MARK: Sidebar of saved transcripts

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Theme.sand).frame(width: 8, height: 8)
                Text("Recap").font(Theme.heading(24))
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 14)

            Button { model.screen = model.job != nil ? .working : .start } label: {
                Label(model.job != nil ? "Transcribing..." : "New Transcription", systemImage: model.job != nil ? "waveform" : "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SidebarRowStyle(selected: model.screen == .start || model.screen == .working))
            .padding(.horizontal, 10)

            SectionLabel(text: "Saved")
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 6)

            if let unsaved = model.unsaved, model.loadError != nil {
                row(unsaved, note: "Not saved").padding(.horizontal, 10)
            }
            if let error = model.loadError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(Theme.font(12)).foregroundColor(Theme.danger).fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") { model.reload() }.buttonStyle(PillButtonStyle(prominent: false))
                }
                .padding(.horizontal, 18)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if let unsaved = model.unsaved {
                            row(unsaved, note: "Not saved")
                        }
                        ForEach(model.saved) { row($0, note: nil) }
                        if model.saved.isEmpty && model.unsaved == nil {
                            Text("Transcripts you make are kept here until you delete them.")
                                .font(Theme.font(12)).foregroundColor(Theme.quiet)
                                .padding(.horizontal, 8).padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                if model.damagedCount > 0 {
                    Text("\(model.damagedCount) saved \(model.damagedCount == 1 ? "file" : "files") couldn't be read and \(model.damagedCount == 1 ? "was" : "were") left in place.")
                        .font(Theme.font(11)).foregroundColor(Theme.warn)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    private func row(_ t: Transcript, note: String?) -> some View {
        Button { model.screen = .transcript(t.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(Theme.font(13, .medium)).lineLimit(1)
                Text(note ?? "\(t.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(TimeFormat.display(t.duration))")
                    .font(Theme.font(11)).foregroundColor(note == nil ? Theme.quiet : Theme.warn).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SidebarRowStyle(selected: model.screen == .transcript(t.id)))
    }
}

struct SidebarRowStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.raised : Color.clear))
            .overlay(alignment: .leading) {
                if selected { RoundedRectangle(cornerRadius: 1).fill(Theme.sand).frame(width: 2).padding(.vertical, 6) }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: Start

struct StartView: View {
    @EnvironmentObject var model: AppModel
    var dropTargeted: Bool

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 8) {
                Text("Transcribe a recording").font(Theme.heading(34))
                Text("Drop in a recording or video and get a searchable transcript with a time on every line. Everything happens on this Mac. Nothing is uploaded.")
                    .font(Theme.font(14)).foregroundColor(Theme.quiet)
                    .multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            VStack(spacing: 14) {
                Image(systemName: "waveform").font(.system(size: 30, weight: .light)).foregroundColor(Theme.sand)
                Text("Drop audio or video files here").font(Theme.font(15, .medium))
                Button("Choose a File...") { model.chooseFiles() }.buttonStyle(PillButtonStyle())
            }
            .frame(maxWidth: 520, minHeight: 190)
            .background(RoundedRectangle(cornerRadius: 14).fill(dropTargeted ? Theme.raised : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(dropTargeted ? Theme.sand : Theme.line, style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))

            HStack(spacing: 10) {
                SectionLabel(text: "Language")
                Picker("", selection: $model.localeID) {
                    if model.locales.isEmpty { Text("Loading...").tag(model.localeID) }
                    ForEach(model.locales, id: \.identifier) { locale in
                        Text(TranscriptionEngine.displayName(locale)).tag(locale.identifier)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
            Spacer()
            Text("Record people only with their consent. Transcripts stay on this Mac until you delete them. Check names and numbers by ear.")
                .font(Theme.font(11.5)).foregroundColor(Theme.quiet)
                .multilineTextAlignment(.center).frame(maxWidth: 520)
                .padding(.bottom, 22)
        }
        .padding(.horizontal, 30)
    }
}

// MARK: Working

struct WorkingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let job = model.job {
                SectionLabel(text: job.preparing ? "Getting ready" : "Transcribing")
                Text(job.title).font(Theme.heading(30)).lineLimit(1)
                ProgressBar(fraction: job.preparing ? nil : job.fraction)
                HStack {
                    Text(job.preparing ? "Preparing the speech engine. The first time for a language, macOS downloads its model."
                                       : "\(Int(job.fraction * 100))% · \(job.lines.count) lines so far")
                        .font(Theme.font(12)).foregroundColor(Theme.quiet)
                    Spacer()
                    if !model.waiting.isEmpty {
                        Text("\(model.waiting.count) waiting").font(Theme.font(12, .medium)).foregroundColor(Theme.sand)
                    }
                    Button("Cancel") { model.cancel() }.buttonStyle(PillButtonStyle(prominent: false))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(job.lines) { line in
                                LineRow(line: line, playing: false, onTime: nil)
                            }
                            if !job.pendingText.isEmpty {
                                Text(job.pendingText).font(Theme.font(14)).foregroundColor(Theme.quiet).padding(.leading, 74)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: job.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
            }
        }
        .padding(28)
        .padding(.top, 10)
    }
}

// MARK: Transcript

struct TranscriptView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var player: Player
    let transcript: Transcript
    @StateObject private var search = SearchState()

    var body: some View {
        let visible = TranscriptSearch.matches(search.text, in: transcript.lines)
        let playingIndex = player.transcriptID == transcript.id ? transcript.lineIndex(at: player.time) : nil
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.saveError, model.unsaved?.id == transcript.id {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(Theme.warn)
                    Text("Not saved yet. \(error)").font(Theme.font(12)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Try Saving Again") { model.trySavingAgain() }.buttonStyle(PillButtonStyle())
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warn.opacity(0.12)))
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transcript.title).font(Theme.heading(30)).lineLimit(1)
                    Text("\(transcript.sourceName) · \(TimeFormat.display(transcript.duration)) · \(transcript.lines.count) lines · \(transcript.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.font(12)).foregroundColor(Theme.quiet).lineLimit(1)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(Theme.quiet)
                    TextField("Search", text: $search.text).textFieldStyle(.plain).font(Theme.font(13))
                    if !search.text.isEmpty {
                        Text("\(visible.count) found").font(Theme.font(11)).foregroundColor(Theme.quiet)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
                .frame(maxWidth: 320)
                Spacer()
                Button("Copy All") { model.copyAll(transcript) }.buttonStyle(PillButtonStyle(prominent: false))
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.label) { model.export(transcript, as: format) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up").labelStyle(.titleOnly)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(PillButtonStyle())
                .fixedSize()
                Button { model.askToDelete(transcript) } label: { Image(systemName: "trash") }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .help("Delete this transcript")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(visible, id: \.self) { index in
                            let line = transcript.lines[index]
                            LineRow(line: line, playing: index == playingIndex) { player.play(transcript, from: line.start) }
                                .id(index)
                        }
                        if visible.isEmpty {
                            Text("No lines match.").font(Theme.font(13)).foregroundColor(Theme.quiet).padding()
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: playingIndex) {
                    if let playingIndex, search.text.isEmpty { withAnimation { proxy.scrollTo(playingIndex, anchor: .center) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
            PlayerBar(transcript: transcript)
        }
        .padding(24)
        .padding(.top, 10)
    }
}

/// A thin sand bar. With no fraction yet (getting ready) it shows a short segment.
struct ProgressBar: View {
    let fraction: Double?
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule().fill(Theme.sand)
                    .frame(width: max(8, geo.size.width * CGFloat(fraction ?? 0.04)))
                    .opacity(fraction == nil ? 0.5 : 1)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Progress")
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "Getting ready")
    }
}

final class DropState: ObservableObject {
    @Published var targeted = false
}

final class SearchState: ObservableObject {
    @Published var text = ""
}

struct LineRow: View {
    let line: Line
    let playing: Bool
    let onTime: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: { onTime?() }) {
                Text(TimeFormat.display(line.start))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(playing ? Theme.ground : Theme.sand)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(playing ? Theme.sand : Color.clear))
                    .frame(width: 62, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(onTime == nil)
            .help(onTime == nil ? "" : "Play from here")
            Text(line.text)
                .font(Theme.font(14))
                .foregroundColor(playing ? Theme.paper : Theme.paper.opacity(0.88))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(playing ? Theme.raised : Color.clear)
    }
}

struct PlayerBar: View {
    @EnvironmentObject var player: Player
    let transcript: Transcript

    var body: some View {
        HStack(spacing: 12) {
            let active = player.transcriptID == transcript.id
            Button {
                if active { player.toggle() } else { player.play(transcript, from: transcript.lines.first?.start ?? 0) }
            } label: {
                Image(systemName: active && player.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(PillButtonStyle(prominent: false))
            Text(active ? "\(TimeFormat.display(player.time)) of \(TimeFormat.display(transcript.duration))" : "Click a time to play from there")
                .font(Theme.font(12)).foregroundColor(Theme.quiet)
            if let problem = player.problem {
                Text(problem).font(Theme.font(12)).foregroundColor(Theme.warn).lineLimit(2)
            }
            Spacer()
        }
        .onDisappear { if player.transcriptID == transcript.id { player.stop() } }
    }
}

// MARK: Dialogs

/// Recap's own dialogs, in the app's look, over the window.
struct DialogView: View {
    @EnvironmentObject var model: AppModel
    let dialog: AppModel.Dialog

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(Theme.heading(24))
                Text(text).font(Theme.font(13)).foregroundColor(Theme.quiet).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    buttons
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
        }
    }

    private var title: String {
        switch dialog {
        case .message(let title, _): return title
        case .confirmDelete: return "Delete this transcript?"
        case .confirmQuit: return "Quit and lose work?"
        }
    }

    private var text: String {
        switch dialog {
        case .message(_, let text): return text
        case .confirmDelete(let t): return "\"\(t.title)\" will be deleted from this Mac. The recording itself isn't touched. This can't be undone."
        case .confirmQuit: return model.quitWarning
        }
    }

    @ViewBuilder private var buttons: some View {
        switch dialog {
        case .message:
            Button("OK") { model.dismissDialog() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
        case .confirmDelete(let t):
            Button("Cancel") { model.dismissDialog() }.buttonStyle(PillButtonStyle(prominent: false)).keyboardShortcut(.cancelAction)
            Button("Delete") { model.dismissDialog(); model.delete(t) }.buttonStyle(PillButtonStyle())
        case .confirmQuit:
            Button("Keep Recap Open") { model.dismissDialog(); model.stayOpen() }
                .buttonStyle(PillButtonStyle(prominent: false)).keyboardShortcut(.cancelAction)
            Button("Quit") { model.dismissDialog(); model.quitAnyway() }.buttonStyle(PillButtonStyle())
        }
    }
}
