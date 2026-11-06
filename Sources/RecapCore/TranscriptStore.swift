import Foundation

/// Saves transcripts as JSON files in one folder (the app's sandbox container) and reads them back.
/// A folder that can't be read is an error, never an empty list. Files that can't be decoded are
/// counted and left where they are, never deleted.
public struct TranscriptStore: Sendable {
    public struct LoadResult: Sendable {
        public var transcripts: [Transcript]
        /// Files in the folder that could not be read. They are kept in place.
        public var damaged: [URL]
    }

    public enum StoreError: LocalizedError {
        case unreadableFolder(String)
        case notSaved(String)

        public var errorDescription: String? {
            switch self {
            case .unreadableFolder(let why): return "Recap couldn't read its saved transcripts. \(why)"
            case .notSaved(let why): return "Recap couldn't save this transcript. \(why)"
            }
        }
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// Application Support/Recap/Transcripts. In the sandbox this is inside the app's container.
    public static func defaultFolder() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appendingPathComponent("Recap/Transcripts", isDirectory: true)
    }

    public func url(for id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json")
    }

    public func loadAll() throws -> LoadResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: folder.path, isDirectory: &isDir) {
            return LoadResult(transcripts: [], damaged: [])  // nothing saved yet
        }
        guard isDir.boolValue else {
            throw StoreError.unreadableFolder("\(folder.path) is a file, not a folder.")
        }
        let names: [URL]
        do {
            names = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            throw StoreError.unreadableFolder(error.localizedDescription)
        }
        var transcripts: [Transcript] = []
        var damaged: [URL] = []
        for file in names where file.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: file)
                let transcript = try TranscriptStore.decoder.decode(Transcript.self, from: data).sanitized()
                transcripts.append(transcript)
            } catch {
                damaged.append(file)
            }
        }
        transcripts.sort { $0.createdAt > $1.createdAt }
        return LoadResult(transcripts: transcripts, damaged: damaged.sorted { $0.path < $1.path })
    }

    public func save(_ transcript: Transcript) throws {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try TranscriptStore.encoder.encode(transcript)
            try data.write(to: url(for: transcript.id), options: [.atomic])
        } catch {
            throw StoreError.notSaved(error.localizedDescription)
        }
    }

    /// Deletes the saved transcript only. The recording is never touched.
    public func delete(_ id: UUID) throws {
        let file = url(for: id)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        // A huge number in a damaged file decodes as a Double and is clamped by sanitized().
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }
}
