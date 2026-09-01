import Foundation
import XCTest
@testable import DiscordVoiceHotkeyCore

final class OggOpusContainerTests: XCTestCase {
    func testParsesVariableLengthOpusPacketsFromCAF() throws {
        let first = Data([0xF8, 0x01, 0x02])
        let second = Data(repeating: 0xAB, count: 260)
        let caf = makeOpusCAF(
            packets: [first, second],
            sampleRate: 48_000,
            primingFrames: 312,
            validFrames: 1_920
        )

        let stream = try CAFPacketStream.parse(caf)

        XCTAssertEqual(stream.sampleRate, 48_000)
        XCTAssertEqual(stream.channelCount, 1)
        XCTAssertEqual(stream.preSkip, 312)
        XCTAssertEqual(stream.packets, [first, second])
    }

    func testCreatesChecksummedOggOpusPages() throws {
        let stream = CAFPacketStream(
            sampleRate: 48_000,
            channelCount: 1,
            preSkip: 312,
            packets: [
                Data([0xF8, 0x01, 0x02]),
                Data([0xF8, 0x03, 0x04]),
            ]
        )

        let ogg = try OggOpusContainer.make(stream: stream, serialNumber: 0x1234_5678)
        let pages = try parseOggPages(ogg)

        XCTAssertEqual(pages.count, 4)
        XCTAssertEqual(pages[0].headerType, 0x02)
        XCTAssertTrue(pages[0].payload.starts(with: Data("OpusHead".utf8)))
        XCTAssertTrue(pages[1].payload.starts(with: Data("OpusTags".utf8)))
        XCTAssertEqual(pages[2].payload, stream.packets[0])
        XCTAssertEqual(pages[3].payload, stream.packets[1])
        XCTAssertEqual(pages[3].headerType, 0x04)
        XCTAssertEqual(pages.map(\.sequence), [0, 1, 2, 3])
        XCTAssertTrue(pages.allSatisfy(\.checksumIsValid))
    }

    func testMacOSAfconvertOutputRemuxesToPlayableOggStructure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("input.wav")
        let caf = directory.appendingPathComponent("output.caf")
        try makeSilentPCM16WAV(sampleRate: 48_000, frameCount: 4_800).write(to: input)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = [
            input.path,
            caf.path,
            "-f", "caff",
            "-d", "opus@48000",
            "-c", "1",
            "-b", "64000",
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let errorText = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, errorText)

        let stream = try CAFPacketStream.parse(Data(contentsOf: caf))
        let ogg = try OggOpusContainer.make(stream: stream, serialNumber: 7)
        let pages = try parseOggPages(ogg)

        XCTAssertEqual(stream.channelCount, 1)
        XCTAssertFalse(stream.packets.isEmpty)
        XCTAssertTrue(pages.first?.payload.starts(with: Data("OpusHead".utf8)) == true)
        XCTAssertEqual(pages.last?.headerType, 0x04)
        XCTAssertTrue(pages.allSatisfy(\.checksumIsValid))
    }
}

private struct ParsedOggPage {
    let headerType: UInt8
    let sequence: UInt32
    let payload: Data
    let checksumIsValid: Bool
}

private func parseOggPages(_ data: Data) throws -> [ParsedOggPage] {
    enum ParseError: Error { case invalid }
    var pages: [ParsedOggPage] = []
    var offset = 0
    while offset < data.count {
        guard offset + 27 <= data.count,
              data.subdata(in: offset..<(offset + 4)) == Data("OggS".utf8) else {
            throw ParseError.invalid
        }
        let segmentCount = Int(data[offset + 26])
        guard offset + 27 + segmentCount <= data.count else { throw ParseError.invalid }
        let payloadSize = (0..<segmentCount).reduce(0) { $0 + Int(data[offset + 27 + $1]) }
        let pageSize = 27 + segmentCount + payloadSize
        guard offset + pageSize <= data.count else { throw ParseError.invalid }
        let pageData = data.subdata(in: offset..<(offset + pageSize))
        var checksumInput = pageData
        checksumInput.replaceSubrange(22..<26, with: repeatElement(UInt8(0), count: 4))
        let storedChecksum = readUInt32LE(pageData, at: 22)
        pages.append(ParsedOggPage(
            headerType: pageData[5],
            sequence: readUInt32LE(pageData, at: 18),
            payload: pageData.subdata(in: (27 + segmentCount)..<pageSize),
            checksumIsValid: storedChecksum == independentOggCRC(checksumInput)
        ))
        offset += pageSize
    }
    return pages
}

private func independentOggCRC(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0
    for byte in data {
        crc ^= UInt32(byte) << 24
        for _ in 0..<8 {
            crc = (crc & 0x8000_0000) != 0
                ? (crc << 1) ^ 0x04C1_1DB7
                : crc << 1
        }
    }
    return crc
}

private func makeOpusCAF(
    packets: [Data],
    sampleRate: Double,
    primingFrames: UInt32,
    validFrames: UInt64
) -> Data {
    var desc = Data()
    desc.appendUInt64BE(sampleRate.bitPattern)
    desc.append(Data("opus".utf8))
    desc.appendUInt32BE(0)
    desc.appendUInt32BE(0)
    desc.appendUInt32BE(960)
    desc.appendUInt32BE(1)
    desc.appendUInt32BE(0)

    var packetTable = Data()
    packetTable.appendUInt64BE(UInt64(packets.count))
    packetTable.appendUInt64BE(validFrames)
    packetTable.appendUInt32BE(primingFrames)
    packetTable.appendUInt32BE(0)
    for packet in packets {
        packetTable.appendCAFVariableLengthInteger(UInt64(packet.count))
    }

    var audioData = Data(repeating: 0, count: 4)
    packets.forEach { audioData.append($0) }

    var result = Data("caff".utf8)
    result.append(contentsOf: [0, 1, 0, 0])
    result.appendCAFChunk(type: "desc", body: desc)
    result.appendCAFChunk(type: "pakt", body: packetTable)
    result.appendCAFChunk(type: "data", body: audioData)
    return result
}

private func makeSilentPCM16WAV(sampleRate: UInt32, frameCount: UInt32) -> Data {
    let dataSize = frameCount * 2
    var wav = Data("RIFF".utf8)
    wav.appendUInt32LE(36 + dataSize)
    wav.append(Data("WAVEfmt ".utf8))
    wav.appendUInt32LE(16)
    wav.appendUInt16LE(1)
    wav.appendUInt16LE(1)
    wav.appendUInt32LE(sampleRate)
    wav.appendUInt32LE(sampleRate * 2)
    wav.appendUInt16LE(2)
    wav.appendUInt16LE(16)
    wav.append(Data("data".utf8))
    wav.appendUInt32LE(dataSize)
    wav.append(Data(repeating: 0, count: Int(dataSize)))
    return wav
}

private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
    (0..<4).reduce(UInt32(0)) { partial, index in
        partial | (UInt32(data[offset + index]) << UInt32(index * 8))
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        for shift in stride(from: 0, through: 24, by: 8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }

    mutating func appendUInt64BE(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }

    mutating func appendCAFVariableLengthInteger(_ value: UInt64) {
        var bytes = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        append(contentsOf: bytes)
    }

    mutating func appendCAFChunk(type: String, body: Data) {
        append(Data(type.utf8))
        appendUInt64BE(UInt64(body.count))
        append(body)
    }
}
