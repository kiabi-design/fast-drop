import Foundation
import Network

// ──────────────────────────────────────────────
// Wire Protocol (compatible with Flutter main.dart)
// ──────────────────────────────────────────────

let kTransferPort: NWEndpoint.Port = 14680
let kDiscoveryPort: NWEndpoint.Port = 14681
let kChunkSize = 1024 * 1024  // 1 MB
let kProtocolVersion: UInt8 = 1
let kMagicBytes: [UInt8] = [0x46, 0x44, 0x52, 0x50] // "FDRP"

enum MessageType: UInt8 {
    case handshake = 0x01
    case handshakeAck = 0x02
    case fileHeader = 0x03
    case chunk = 0x04
    case chunkAck = 0x05
    case done = 0x06
    case cancel = 0x07
    case error = 0xFF
}

struct FastDropHeader {
    let magic: UInt32
    let version: UInt8
    let type: MessageType
    let flags: UInt8
    let sequence: UInt32
    let payloadLength: UInt32

    static let size = 16

    init(type: MessageType, sequence: UInt32, payloadLength: UInt32, flags: UInt8 = 0) {
        self.magic = UInt32(kMagicBytes[0]) << 24 | UInt32(kMagicBytes[1]) << 16 | UInt32(kMagicBytes[2]) << 8 | UInt32(kMagicBytes[3])
        self.version = kProtocolVersion
        self.type = type
        self.flags = flags
        self.sequence = sequence
        self.payloadLength = payloadLength
    }

    func encode() -> Data {
        var data = Data()
        data.append(withUnsafeBytes(of: magic.bigEndian) { Data($0) })
        data.append(version)
        data.append(type.rawValue)
        data.append(flags)
        data.append(withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: payloadLength.bigEndian) { Data($0) })
        return data
    }

    static func decode(_ data: Data) -> FastDropHeader? {
        guard data.count >= size else { return nil }
        let magic = data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard magic == UInt32(kMagicBytes[0]) << 24 | UInt32(kMagicBytes[1]) << 16 | UInt32(kMagicBytes[2]) << 8 | UInt32(kMagicBytes[3]) else { return nil }
        let version = data[4]
        guard version == kProtocolVersion else { return nil }
        let type = MessageType(rawValue: data[5]) ?? .error
        let flags = data[6]
        let sequence = data[7..<11].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let payloadLength = data[11..<15].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        var header = FastDropHeader(type: type, sequence: sequence, payloadLength: payloadLength, flags: flags)
        return header
    }
}

// ──────────────────────────────────────────────
// Payloads
// ──────────────────────────────────────────────

struct HandshakePayload: Codable {
    let deviceName: String
    let deviceType: String  // "iPhone", "iPad", "Mac"
    let protocolVersion: Int
    let capabilities: [String]  // ["resume", "compression", "encryption"]
}

struct FileHeaderPayload: Codable {
    let fileId: String
    let fileName: String
    let fileSize: Int64
    let mimeType: String
    let checksum: String?  // SHA256 hex
    let chunkCount: Int
}

struct ChunkPayload {
    let fileId: String
    let chunkIndex: Int
    let data: Data
    let isLast: Bool
}

struct ChunkAckPayload: Codable {
    let fileId: String
    let chunkIndex: Int
    let receivedBytes: Int64
}

struct DonePayload: Codable {
    let fileId: String
    let totalBytes: Int64
    let checksum: String?
}

struct ErrorPayload: Codable {
    let code: Int
    let message: String
}

// ──────────────────────────────────────────────
// Discovery (Bonjour)
// ──────────────────────────────────────────────

let kServiceType = "_fastdrop._tcp"
let kServiceDomain = "local."

struct DiscoveredPeer: Identifiable, Hashable {
    let id = UUID()
    let endpoint: NWEndpoint
    let name: String
    let deviceType: String
    var ipAddress: String?
    var port: UInt16?
    var lastSeen: Date = Date()
}

// ──────────────────────────────────────────────
// Transfer Session
// ──────────────────────────────────────────────

enum TransferDirection { case send, receive }

struct TransferFile: Identifiable {
    let id = UUID()
    let fileId: String
    let name: String
    let size: Int64
    let mimeType: String
    let url: URL?  // local file URL for sending, destination for receiving
    var progress: Float = 0
    var speed: Double = 0  // bytes/sec
    var status: TransferStatus = .waiting
    var error: String?
}

enum TransferStatus {
    case waiting
    case connecting
    case transferring
    case paused
    case completed
    case failed
    case cancelled
}

final class TransferSession: ObservableObject {
    let id = UUID()
    let direction: TransferDirection
    let peer: DiscoveredPeer
    @Published var files: [TransferFile] = []
    @Published var overallProgress: Float = 0
    @Published var totalSpeed: Double = 0
    @Published var status: TransferStatus = .waiting
    @Published var error: String?

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    var transferredBytes: Int64 { files.reduce(0) { $0 + Int64(Float($1.size) * $1.progress) } }
}