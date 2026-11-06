import AVFoundation
import Combine
import Foundation
import RecapCore

/// Plays the original recording from a saved bookmark, so a click on a time plays from there.
/// Watches the player item's status, so a recording that can't be played shows a message.
@MainActor
final class Player: ObservableObject {
    @Published private(set) var transcriptID: UUID?
    @Published private(set) var time: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var problem: String?

    private var player: AVPlayer?
    private var observer: Any?
    private var statusWatch: AnyCancellable?
    private var rateWatch: AnyCancellable?
    private var scopedURL: URL?
    /// Called with a fresh bookmark when the saved one is stale (the recording moved), so it can be saved.
    var onBookmarkRefresh: ((UUID, Data) -> Void)?

    func play(_ transcript: Transcript, from seconds: Double) {
        problem = nil
        if transcriptID != transcript.id || player == nil {
            guard load(transcript) else { return }
        }
        let target = CMTime(seconds: TimeFormat.clamp(seconds), preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
    }

    func toggle() {
        guard let player else { return }
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func stop() {
        player?.pause()
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        statusWatch = nil
        rateWatch = nil
        player = nil
        transcriptID = nil
        isPlaying = false
        time = 0
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private func load(_ transcript: Transcript) -> Bool {
        stop()
        guard let bookmark = transcript.bookmark else {
            problem = "Recap doesn't know where this recording is, so it can't play it."
            return false
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            problem = "The recording has moved or been deleted, so it can't be played."
            return false
        }
        guard url.isFileURL else {
            problem = "Recap can only play files on this Mac."
            return false
        }
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                     includingResourceValuesForKeys: nil, relativeTo: nil) {
            onBookmarkRefresh?(transcript.id, fresh)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            problem = "The recording has moved or been deleted, so it can't be played."
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = nil
            return false
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        transcriptID = transcript.id
        statusWatch = item.publisher(for: \.status).receive(on: DispatchQueue.main).sink { [weak self] status in
            if status == .failed {
                self?.problem = "This recording can't be played. \(item.error?.localizedDescription ?? "")"
                self?.isPlaying = false
            }
        }
        rateWatch = player.publisher(for: \.rate).receive(on: DispatchQueue.main).sink { [weak self] rate in
            self?.isPlaying = rate != 0
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                  queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.time = t.seconds.isFinite ? t.seconds : 0 }
        }
        return true
    }
}
