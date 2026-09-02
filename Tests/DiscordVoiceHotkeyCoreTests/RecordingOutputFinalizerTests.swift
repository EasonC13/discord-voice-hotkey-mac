import Foundation
import XCTest
@testable import DiscordVoiceHotkeyCore

final class RecordingOutputFinalizerTests: XCTestCase {
    func testSuccessfulConversionReturnsOggAndRemovesAACSource() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("voice-20260901-194014-725.m4a")
        try Data("aac-source".utf8).write(to: source)
        var receivedDestination: URL?
        let finalizer = RecordingOutputFinalizer { receivedSource, destination in
            XCTAssertEqual(receivedSource, source)
            receivedDestination = destination
            try Data("OggS-test".utf8).write(to: destination)
        }

        let result = finalizer.finalize(source: source)

        XCTAssertEqual(result.pathExtension, "ogg")
        XCTAssertEqual(receivedDestination, result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }

    func testFailedConversionReturnsOriginalAACWithoutDeletingIt() throws {
        enum ExpectedFailure: Error { case conversion }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("voice-20260901-194014-725.m4a")
        try Data("aac-source".utf8).write(to: source)
        let finalizer = RecordingOutputFinalizer { _, _ in
            throw ExpectedFailure.conversion
        }

        let result = finalizer.finalize(source: source)

        XCTAssertEqual(result, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: source.deletingPathExtension().appendingPathExtension("ogg").path
        ))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
