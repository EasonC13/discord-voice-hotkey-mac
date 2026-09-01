import Foundation

public struct CAFPacketStream: Equatable {
    public let sampleRate: Double
    public let channelCount: UInt8
    public let preSkip: UInt16
    public let packets: [Data]

    public init(
        sampleRate: Double,
        channelCount: UInt8,
        preSkip: UInt16,
        packets: [Data]
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.preSkip = preSkip
        self.packets = packets
    }

    public static func parse(_ data: Data) throws -> CAFPacketStream {
        var reader = BinaryReader(data)
        guard try reader.readASCII(count: 4) == "caff" else {
            throw CAFPacketStreamError.invalidHeader
        }
        _ = try reader.readUInt16BE()
        _ = try reader.readUInt16BE()

        var description: AudioDescription?
        var packetSizes: [Int]?
        var preSkip: UInt16 = 0
        var audioBytes: Data?

        while reader.remaining >= 12 {
            let type = try reader.readASCII(count: 4)
            let rawSize = try reader.readUInt64BE()
            guard rawSize <= UInt64(reader.remaining) else {
                throw CAFPacketStreamError.truncatedChunk(type)
            }
            let body = try reader.readData(count: Int(rawSize))

            switch type {
            case "desc":
                var descReader = BinaryReader(body)
                let sampleRate = Double(bitPattern: try descReader.readUInt64BE())
                let formatID = try descReader.readASCII(count: 4)
                _ = try descReader.readUInt32BE()
                let bytesPerPacket = try descReader.readUInt32BE()
                _ = try descReader.readUInt32BE()
                let channelCount = try descReader.readUInt32BE()
                _ = try descReader.readUInt32BE()
                description = AudioDescription(
                    sampleRate: sampleRate,
                    formatID: formatID,
                    bytesPerPacket: bytesPerPacket,
                    channelCount: channelCount
                )
            case "pakt":
                var tableReader = BinaryReader(body)
                let packetCount = try tableReader.readUInt64BE()
                _ = try tableReader.readUInt64BE()
                let primingFrames = try tableReader.readUInt32BE()
                _ = try tableReader.readUInt32BE()
                guard packetCount <= UInt64(Int.max) else {
                    throw CAFPacketStreamError.invalidPacketTable
                }
                var sizes: [Int] = []
                sizes.reserveCapacity(Int(packetCount))
                for _ in 0..<Int(packetCount) {
                    let size = try tableReader.readCAFVariableLengthInteger()
                    guard size <= UInt64(Int.max) else {
                        throw CAFPacketStreamError.invalidPacketTable
                    }
                    sizes.append(Int(size))
                }
                packetSizes = sizes
                preSkip = UInt16(clamping: primingFrames)
            case "data":
                guard body.count >= 4 else {
                    throw CAFPacketStreamError.invalidAudioData
                }
                audioBytes = body.subdata(in: 4..<body.count)
            default:
                break
            }
        }

        guard let description else { throw CAFPacketStreamError.missingDescription }
        guard description.formatID == "opus" else {
            throw CAFPacketStreamError.unsupportedFormat(description.formatID)
        }
        guard description.channelCount > 0, description.channelCount <= UInt32(UInt8.max) else {
            throw CAFPacketStreamError.invalidChannelCount
        }
        guard let audioBytes else { throw CAFPacketStreamError.missingAudioData }

        let sizes: [Int]
        if let packetSizes {
            sizes = packetSizes
        } else if description.bytesPerPacket > 0 {
            let packetSize = Int(description.bytesPerPacket)
            guard packetSize > 0, audioBytes.count.isMultiple(of: packetSize) else {
                throw CAFPacketStreamError.invalidPacketTable
            }
            sizes = Array(repeating: packetSize, count: audioBytes.count / packetSize)
        } else {
            throw CAFPacketStreamError.missingPacketTable
        }

        var packets: [Data] = []
        packets.reserveCapacity(sizes.count)
        var offset = 0
        for size in sizes {
            guard size >= 0, offset <= audioBytes.count - size else {
                throw CAFPacketStreamError.invalidPacketTable
            }
            packets.append(audioBytes.subdata(in: offset..<(offset + size)))
            offset += size
        }
        guard offset == audioBytes.count else {
            throw CAFPacketStreamError.invalidPacketTable
        }

        return CAFPacketStream(
            sampleRate: description.sampleRate,
            channelCount: UInt8(description.channelCount),
            preSkip: preSkip,
            packets: packets
        )
    }
}

public enum CAFPacketStreamError: LocalizedError {
    case invalidHeader
    case truncated
    case truncatedChunk(String)
    case missingDescription
    case unsupportedFormat(String)
    case invalidChannelCount
    case missingPacketTable
    case invalidPacketTable
    case missingAudioData
    case invalidAudioData

    public var errorDescription: String? {
        switch self {
        case .invalidHeader: return "The converted audio is not a CAF file."
        case .truncated: return "The converted CAF file is truncated."
        case .truncatedChunk(let type): return "The CAF \(type) chunk is truncated."
        case .missingDescription: return "The CAF audio description is missing."
        case .unsupportedFormat(let format): return "Expected Opus audio, found \(format)."
        case .invalidChannelCount: return "The CAF channel count is invalid."
        case .missingPacketTable: return "The CAF Opus packet table is missing."
        case .invalidPacketTable: return "The CAF Opus packet table is invalid."
        case .missingAudioData: return "The CAF audio data is missing."
        case .invalidAudioData: return "The CAF audio data is invalid."
        }
    }
}

public enum OggOpusContainerError: LocalizedError {
    case noPackets
    case unsupportedChannelCount
    case invalidPacket

    public var errorDescription: String? {
        switch self {
        case .noPackets: return "The Opus stream contains no packets."
        case .unsupportedChannelCount: return "Only mono and stereo Opus streams are supported."
        case .invalidPacket: return "The Opus stream contains an invalid packet."
        }
    }
}

public enum OggOpusContainer {
    public static func make(
        stream: CAFPacketStream,
        serialNumber: UInt32 = UInt32.random(in: UInt32.min...UInt32.max)
    ) throws -> Data {
        guard !stream.packets.isEmpty else { throw OggOpusContainerError.noPackets }
        guard stream.channelCount == 1 || stream.channelCount == 2 else {
            throw OggOpusContainerError.unsupportedChannelCount
        }

        var output = Data()
        var sequence: UInt32 = 0

        var opusHead = Data("OpusHead".utf8)
        opusHead.append(1)
        opusHead.append(stream.channelCount)
        opusHead.appendUInt16LE(stream.preSkip)
        let inputRate = UInt32(clamping: Int(stream.sampleRate.rounded()))
        opusHead.appendUInt32LE(inputRate)
        opusHead.appendUInt16LE(0)
        opusHead.append(0)
        output.append(makePage(
            payload: opusHead,
            headerType: 0x02,
            granulePosition: UInt64.max,
            serialNumber: serialNumber,
            sequence: sequence
        ))
        sequence += 1

        let vendor = Data("Discord Voice Hotkey".utf8)
        var opusTags = Data("OpusTags".utf8)
        opusTags.appendUInt32LE(UInt32(vendor.count))
        opusTags.append(vendor)
        opusTags.appendUInt32LE(0)
        output.append(makePage(
            payload: opusTags,
            headerType: 0,
            granulePosition: UInt64.max,
            serialNumber: serialNumber,
            sequence: sequence
        ))
        sequence += 1

        var granulePosition: UInt64 = 0
        for (index, packet) in stream.packets.enumerated() {
            let samples = try opusSampleCount(at48KHz: packet)
            granulePosition += UInt64(samples)
            output.append(makePage(
                payload: packet,
                headerType: index == stream.packets.count - 1 ? 0x04 : 0,
                granulePosition: granulePosition,
                serialNumber: serialNumber,
                sequence: sequence
            ))
            sequence += 1
        }
        return output
    }

    private static func opusSampleCount(at48KHz packet: Data) throws -> Int {
        guard let toc = packet.first else { throw OggOpusContainerError.invalidPacket }
        let configuration = Int(toc >> 3)
        let samplesPerFrame: Int
        if configuration < 12 {
            samplesPerFrame = [480, 960, 1_920, 2_880][configuration & 0x03]
        } else if configuration < 16 {
            samplesPerFrame = [480, 960][configuration & 0x01]
        } else {
            samplesPerFrame = [120, 240, 480, 960][configuration & 0x03]
        }

        let frameCode = toc & 0x03
        let frameCount: Int
        switch frameCode {
        case 0:
            frameCount = 1
        case 1, 2:
            frameCount = 2
        default:
            guard packet.count >= 2 else { throw OggOpusContainerError.invalidPacket }
            frameCount = Int(packet[packet.startIndex + 1] & 0x3F)
            guard frameCount > 0 else { throw OggOpusContainerError.invalidPacket }
        }
        let total = samplesPerFrame * frameCount
        guard total <= 5_760 else { throw OggOpusContainerError.invalidPacket }
        return total
    }

    private static func makePage(
        payload: Data,
        headerType: UInt8,
        granulePosition: UInt64,
        serialNumber: UInt32,
        sequence: UInt32
    ) -> Data {
        var lacing = [UInt8](repeating: 255, count: payload.count / 255)
        lacing.append(UInt8(payload.count % 255))

        var page = Data("OggS".utf8)
        page.append(0)
        page.append(headerType)
        page.appendUInt64LE(granulePosition)
        page.appendUInt32LE(serialNumber)
        page.appendUInt32LE(sequence)
        page.appendUInt32LE(0)
        page.append(UInt8(lacing.count))
        page.append(contentsOf: lacing)
        page.append(payload)

        let checksum = oggCRC(page)
        page.replaceSubrange(22..<26, with: checksum.littleEndianBytes)
        return page
    }

    private static func oggCRC(_ data: Data) -> UInt32 {
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
}

private struct AudioDescription {
    let sampleRate: Double
    let formatID: String
    let bytesPerPacket: UInt32
    let channelCount: UInt32
}

private struct BinaryReader {
    private let data: Data
    private(set) var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var remaining: Int { data.count - offset }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset <= data.count - count else {
            throw CAFPacketStreamError.truncated
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readASCII(count: Int) throws -> String {
        let bytes = try readData(count: count)
        guard let value = String(data: bytes, encoding: .ascii) else {
            throw CAFPacketStreamError.truncated
        }
        return value
    }

    mutating func readUInt16BE() throws -> UInt16 {
        let bytes = try readData(count: 2)
        return bytes.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    mutating func readUInt32BE() throws -> UInt32 {
        let bytes = try readData(count: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64BE() throws -> UInt64 {
        let bytes = try readData(count: 8)
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func readCAFVariableLengthInteger() throws -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<10 {
            let byte = try readData(count: 1)[0]
            guard value <= UInt64.max >> 7 else {
                throw CAFPacketStreamError.invalidPacketTable
            }
            value = (value << 7) | UInt64(byte & 0x7F)
            if (byte & 0x80) == 0 { return value }
        }
        throw CAFPacketStreamError.invalidPacketTable
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        (0..<4).map { UInt8((self >> UInt32($0 * 8)) & 0xFF) }
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: value.littleEndianBytes)
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) {
            append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }
}
