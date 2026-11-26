import Foundation
import Network

// ──────────────────────────────────────────────
// Wire Protocol (compatible with Flutter main.dart)
// ──────────────────────────────────────────────

public let kTransferPort: NWEndpoint.Port = 14680
public let kDiscoveryPort: NWEndpoint.Port = 14681
public let kChunkSize = 1024 * 1024  // 1 MB
public let kProtocolVersion: UInt8 = 1
public let kMagicBytes: [UInt8] = [0x46, 0x44, 0x52, 0x50] // "FDRP"

public enum MessageType: UInt8 {
    case handshake = 0x01
    case handshakeAck = 0x02
    case fileHeader = 0x03
    case chunk = 0x04
    case chunkAck = 0x05
    case done = 0x06
    case cancel = 0x07
    case error = 0xFF
}

public struct FastDropHeader {
    public let magic: UInt32
    public let version: UInt8
    public let type: MessageType
    public let flags: UInt8
    public let sequence: UInt32
    public let payloadLength: UInt32

    public static let size = 16

    public init(type: MessageType, sequence: UInt32, payloadLength: UInt32, flags: UInt8 = 0) {
        self.magic = UInt32(kMagicBytes[0]) << 24 | UInt32(kMagicBytes[1]) << 16 | UInt32(kMagicBytes[2]) << 8 | UInt32(kMagicBytes[3])
        self.version = kProtocolVersion
        self.type = type
        self.flags = flags
        self.sequence = sequence
        self.payloadLength = payloadLength
    }

    public func encode() -> Data {
        var data = Data()
        data.append(withUnsafeBytes(of: magic.bigEndian) { Data($0) })
        data.append(version)
        data.append(type.rawValue)
        data.append(flags)
        data.append(withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: payloadLength.bigEndian) { Data($0) })
        return data
    }

    public static func decode(_ data: Data) -> FastDropHeader? {
        guard data.count >= size else { return nil }
        let magic = data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard magic == UInt32(kMagicBytes[0]) << 24 | UInt32(kMagicBytes[1]) << 16 | UInt32(kMagicBytes[2]) << 8 | UInt32(kMagicBytes[3]) else { return nil }
        let version = data[4]
        guard version == kProtocolVersion else { return nil }
        let type = MessageType(rawValue: data[5]) ?? .error
        let flags = data[6]
        let sequence = data[7..<11].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let payloadLength = data[11..<15].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let header = FastDropHeader(type: type, sequence: sequence, payloadLength: payloadLength, flags: flags)
        return header
    }
}

// ──────────────────────────────────────────────
// Payloads
// ──────────────────────────────────────────────

public struct HandshakePayload: Codable {
    public let deviceName: String
    public let deviceType: String  // "iPhone", "iPad", "Mac"
    public let protocolVersion: Int
    public let capabilities: [String]  // ["resume", "compression", "encryption"]

    public init(deviceName: String, deviceType: String, protocolVersion: Int, capabilities: [String]) {
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
    }
}

public struct FileHeaderPayload: Codable {
    public let fileId: String
    public let fileName: String
    public let fileSize: Int64
    public let mimeType: String
    public let checksum: String?  // SHA256 hex
    public let chunkCount: Int

    public init(fileId: String, fileName: String, fileSize: Int64, mimeType: String, checksum: String?, chunkCount: Int) {
        self.fileId = fileId
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.checksum = checksum
        self.chunkCount = chunkCount
    }
}

public struct ChunkPayload {
    public let fileId: String
    public let chunkIndex: Int
    public let data: Data
    public let isLast: Bool

    public init(fileId: String, chunkIndex: Int, data: Data, isLast: Bool) {
        self.fileId = fileId
        self.chunkIndex = chunkIndex
        self.data = data
        self.isLast = isLast
    }
}

public struct ChunkAckPayload: Codable {
    public let fileId: String
    public let chunkIndex: Int
    public let receivedBytes: Int64

    public init(fileId: String, chunkIndex: Int, receivedBytes: Int64) {
        self.fileId = fileId
        self.chunkIndex = chunkIndex
        self.receivedBytes = receivedBytes
    }
}

public struct DonePayload: Codable {
    public let fileId: String
    public let totalBytes: Int64
    public let checksum: String?

    public init(fileId: String, totalBytes: Int64, checksum: String?) {
        self.fileId = fileId
        self.totalBytes = totalBytes
        self.checksum = checksum
    }
}

public struct ErrorPayload: Codable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

// ──────────────────────────────────────────────
// Discovery (Bonjour)
// ──────────────────────────────────────────────

public let kServiceType = "_fastdrop._tcp"
public let kServiceDomain = "local."

// Use class for @unchecked Sendable conformance (avoids Swift 6 captured var issues)
public final class DiscoveredPeer: Identifiable, Hashable, @unchecked Sendable {
    public let id = UUID()
    public let endpoint: NWEndpoint
    public let name: String
    public let deviceType: String
    public var ipAddress: String?
    public var port: UInt16?
    public var lastSeen: Date = Date()

    public init(endpoint: NWEndpoint, name: String, deviceType: String) {
        self.endpoint = endpoint
        self.name = name
        self.deviceType = deviceType
    }

    // Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    public static func == (lhs: DiscoveredPeer, rhs: DiscoveredPeer) -> Bool {
        lhs.id == rhs.id
    }
}

// ──────────────────────────────────────────────
// Transfer Session
// ──────────────────────────────────────────────

public enum TransferDirection { case send, receive }

public struct TransferFile: Identifiable {
    public let id = UUID()
    public let fileId: String
    public let name: String
    public let size: Int64
    public let mimeType: String
    public let url: URL?  // local file URL for sending, destination for receiving
    public var progress: Float = 0
    public var speed: Double = 0  // bytes/sec
    public var status: TransferStatus = .waiting
    public var error: String?

    public init(fileId: String, name: String, size: Int64, mimeType: String, url: URL?) {
        self.fileId = fileId
        self.name = name
        self.size = size
        self.mimeType = mimeType
        self.url = url
    }
}

public enum TransferStatus {
    case waiting
    case connecting
    case transferring
    case paused
    case completed
    case failed
    case cancelled
}

public final class TransferSession: ObservableObject, @unchecked Sendable {
    public let id = UUID()
    public let direction: TransferDirection
    public let peer: DiscoveredPeer
    @Published public var files: [TransferFile] = []
    @Published public var overallProgress: Float = 0
    @Published public var totalSpeed: Double = 0
    @Published public var status: TransferStatus = .waiting
    @Published public var error: String?

    public init(direction: TransferDirection, peer: DiscoveredPeer, files: [TransferFile]) {
        self.direction = direction
        self.peer = peer
        self.files = files
    }

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    public var transferredBytes: Int64 { files.reduce(0) { $0 + Int64(Float($1.size) * $1.progress) } }
}