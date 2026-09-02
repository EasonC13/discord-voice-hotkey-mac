import Foundation

public struct RecordingOutputFinalizer {
    public typealias Convert = (_ source: URL, _ destination: URL) throws -> Void

    private let convert: Convert

    public init(convert: @escaping Convert) {
        self.convert = convert
    }

    public init() {
        self.init { source, destination in
            try MacOggOpusConverter().convert(source: source, destination: destination)
        }
    }

    public func finalize(source: URL) -> URL {
        let destination = source
            .deletingPathExtension()
            .appendingPathExtension("ogg")
        do {
            try convert(source, destination)
            guard FileManager.default.fileExists(atPath: destination.path) else {
                return source
            }
            try FileManager.default.removeItem(at: source)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return source
        }
    }
}
