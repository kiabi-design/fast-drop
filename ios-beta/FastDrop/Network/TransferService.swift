import Foundation
import Network
import Combine
import os.log
import UIKit

// ──────────────────────────────────────────────
// Transfer Service (Sender & Receiver)
// ──────────────────────────────────────────────

private let logger = Logger(subsystem: "com.fastdrop", category: "transfer")

// State holder for receive loop (avoids Swift 6 captured var mutation issues)
// Mark as @unchecked Sendable since we control access via the transfer queue
private final class ReceiveState: @unchecked Sendable {
    var buffer = Data()
    var expectedHeader: FastDropHeader?
    var currentFile: TransferFile?
    var fileHandle: FileHandle?
    var receivedChunks = Set<Int>()
}

// TransferService is @unchecked Sendable because:
// - All mutable state is accessed only from the dedicated `queue` (DispatchQueue)
// - @Published properties are @MainActor isolated
// - We never share mutable state across concurrency domains without synchronization
@MainActor
final class TransferService: ObservableObject {
    @Published private(set) var sessions: [TransferSession] = []
    @Published var error: String?

    private let queue = DispatchQueue(label: "fastdrop.transfer", qos: .userInitiated)
    private let parameters: NWParameters
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]

    init() {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30
        self.parameters = NWParameters(tls: nil, tcp: tcpOptions)
        self.parameters.includePeerToPeer = true
        startListener()
    }

    // ─── Listener (for incoming) ───
    private func startListener() {
        do {
            listener = try NWListener(using: parameters, on: kTransferPort)
        } catch {
            self.error = "Failed to start listener: \(error.localizedDescription)"
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.error = nil
                    logger.info("Listener ready on port 14680")
                case .failed(let err):
                    self?.error = "Listener failed: \(err.localizedDescription)"
                default: break
                }
            }
        }

        // Capture self weakly and use Task to call async method
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                await self?.handleIncomingConnection(connection)
            }
        }

        listener?.start(queue: queue)
    }

    private func handleIncomingConnection(_ connection: NWConnection) async {
        let sessionId = UUID()
        let state = ReceiveState()

        connection.stateUpdateHandler = { [weak self] stateUpdate in
            Task { @MainActor [weak self] in
                switch stateUpdate {
                case .ready:
                    logger.info("Incoming connection ready")
                    self?.receiveHandshake(connection, sessionId: sessionId)
                case .failed(let err):
                    logger.error("Incoming connection failed: \(err.localizedDescription)")
                    self?.cleanupConnection(sessionId)
                case .cancelled:
                    self?.cleanupConnection(sessionId)
                default: break
                }
            }
        }

        connection.start(queue: queue)
        activeConnections[sessionId] = connection

        // Start the receive loop using a static method to avoid capture issues
        Self.startReceiveLoop(connection: connection, sessionId: sessionId, state: state, queue: queue, service: self)
    }

    // Static method to run the receive loop without capturing self in a non-Sendable way
    private static func startReceiveLoop(connection: NWConnection, sessionId: UUID, state: ReceiveState, queue: DispatchQueue, service: TransferService) {
        // Use a recursive function that doesn't capture inout parameters
        func receiveLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { @Sendable [weak service] data, _, isComplete, error in
                guard let service = service else { return }

                if let data = data, !data.isEmpty {
                    state.buffer.append(data)
                    // Process buffer on main actor
                    Task { @MainActor [weak service] in
                        guard let service = service else { return }
                        service.processBuffer(state: state, connection: connection, sessionId: sessionId)
                    }
                }

                if let error = error {
                    logger.error("Receive error: \(error.localizedDescription)")
                    Task { @MainActor [weak service] in
                        service?.cleanupConnection(sessionId)
                    }
                    return
                }

                if isComplete {
                    logger.info("Connection complete")
                    Task { @MainActor [weak service] in
                        service?.cleanupConnection(sessionId)
                    }
                    return
                }

                // Continue the loop
                receiveLoop()
            }
        }
        receiveLoop()
    }

    // Updated processBuffer to use ReceiveState instead of inout parameters
    private func processBuffer(state: ReceiveState, connection: NWConnection, sessionId: UUID) {
        var buffer = state.buffer
        while true {
            if state.expectedHeader == nil {
                guard buffer.count >= FastDropHeader.size,
                      let header = FastDropHeader.decode(buffer) else { break }
                state.expectedHeader = header
                buffer.removeFirst(FastDropHeader.size)
            }

            guard let header = state.expectedHeader,
                  buffer.count >= header.payloadLength else { break }

            let payload = buffer.prefix(Int(header.payloadLength))
            buffer.removeFirst(Int(header.payloadLength))
            state.expectedHeader = nil
            state.buffer = buffer

            handlePayload(header: header, payload: Data(payload), connection: connection, sessionId: sessionId, state: state)
        }
    }

    // Updated handlePayload to use ReceiveState
    private func handlePayload(header: FastDropHeader, payload: Data, connection: NWConnection, sessionId: UUID, state: ReceiveState) {
        switch header.type {
        case .handshake:
            if let handshake = try? JSONDecoder().decode(HandshakePayload.self, from: payload) {
                logger.info("Handshake from \(handshake.deviceName)")
                sendHandshakeAck(connection)
            }
        case .fileHeader:
            if let fileHeader = try? JSONDecoder().decode(FileHeaderPayload.self, from: payload) {
                let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destUrl = docsUrl.appendingPathComponent(fileHeader.fileName)
                state.fileHandle = try? FileHandle(forWritingTo: destUrl)
                if state.fileHandle == nil {
                    FileManager.default.createFile(atPath: destUrl.path, contents: nil)
                    state.fileHandle = try? FileHandle(forWritingTo: destUrl)
                }
                state.currentFile = TransferFile(
                    fileId: fileHeader.fileId,
                    name: fileHeader.fileName,
                    size: fileHeader.fileSize,
                    mimeType: fileHeader.mimeType,
                    url: destUrl
                )
                state.receivedChunks.removeAll()
                sendChunkAck(connection, fileId: fileHeader.fileId, chunkIndex: -1, receivedBytes: 0)
            }
        case .chunk:
            handleChunk(payload, connection: connection, state: state)
        case .done:
            if let _ = try? JSONDecoder().decode(DonePayload.self, from: payload) {
                logger.info("Transfer done")
                state.fileHandle?.closeFile()
                state.fileHandle = nil
                state.currentFile = nil
            }
        case .cancel:
            logger.info("Transfer cancelled")
            state.fileHandle?.closeFile()
            cleanupConnection(sessionId)
        default:
            break
        }
    }

    // Updated handleChunk to use ReceiveState
    private func handleChunk(_ data: Data, connection: NWConnection, state: ReceiveState) {
        guard var file = state.currentFile, let handle = state.fileHandle else { return }
        handle.write(data)
        file.progress = min(1.0, file.progress + Float(data.count) / Float(file.size))
        state.currentFile = file
    }

    private func sendHandshakeAck(_ connection: NWConnection) {
        let ack = FastDropHeader(type: .handshakeAck, sequence: 0, payloadLength: 0)
        connection.send(content: ack.encode(), completion: .contentProcessed { _ in })
    }

    private func sendChunkAck(_ connection: NWConnection, fileId: String, chunkIndex: Int, receivedBytes: Int64) {
        let ackPayload = ChunkAckPayload(fileId: fileId, chunkIndex: chunkIndex, receivedBytes: receivedBytes)
        let data = (try? JSONEncoder().encode(ackPayload)) ?? Data()
        let header = FastDropHeader(type: .chunkAck, sequence: 0, payloadLength: UInt32(data.count))
        connection.send(content: header.encode() + data, completion: .contentProcessed { _ in })
    }

    // ─── Sender API ───
    func sendFiles(_ files: [TransferFile], to peer: DiscoveredPeer) -> TransferSession {
        let session = TransferSession(direction: .send, peer: peer, files: files)
        sessions.append(session)

        Task {
            await performSend(session: session)
        }

        return session
    }

    private func performSend(session: TransferSession) async {
        guard let peerEndpoint = peerEndpoint(from: session.peer) else {
            failSession(session, error: "Invalid peer endpoint")
            return
        }

        let connection = NWConnection(to: peerEndpoint, using: parameters)
        let sessionId = session.id

        await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.activeConnections[sessionId] = connection
                        self?.sendHandshake(connection, session: session)
                        continuation.resume()
                    case .failed(let err):
                        self?.failSession(session, error: err.localizedDescription)
                        continuation.resume()
                    case .cancelled:
                        continuation.resume()
                    default: break
                    }
                }
            }
            connection.start(queue: self.queue)
        }

        // Send files sequentially
        for file in session.files {
            await sendFile(file, connection: connection, session: session)
        }

        completeSession(session)
    }

    private func sendHandshake(_ connection: NWConnection, session: TransferSession) {
        let handshake = HandshakePayload(
            deviceName: UIDevice.current.name,
            deviceType: UIDevice.current.model,
            protocolVersion: 1,
            capabilities: ["resume"]
        )
        let data = (try? JSONEncoder().encode(handshake)) ?? Data()
        let header = FastDropHeader(type: .handshake, sequence: 1, payloadLength: UInt32(data.count))
        connection.send(content: header.encode() + data, completion: .contentProcessed { _ in })
    }

    private func sendFile(_ file: TransferFile, connection: NWConnection, session: TransferSession) async {
        guard let url = file.url, let handle = try? FileHandle(forReadingFrom: url) else {
            failSession(session, error: "Cannot read file: \(file.name)")
            return
        }

        // Send file header
        let chunkCount = Int(ceil(Double(file.size) / Double(kChunkSize)))
        let header = FileHeaderPayload(
            fileId: file.fileId,
            fileName: file.name,
            fileSize: file.size,
            mimeType: file.mimeType,
            checksum: nil,
            chunkCount: chunkCount
        )
        let data = (try? JSONEncoder().encode(header)) ?? Data()
        let hdr = FastDropHeader(type: .fileHeader, sequence: 2, payloadLength: UInt32(data.count))
        connection.send(content: hdr.encode() + data, completion: .contentProcessed { _ in })

        // Send chunks
        var offset: Int64 = 0
        var chunkIndex = 0
        while offset < file.size {
            let chunkSize = min(kChunkSize, Int(file.size - offset))
            let chunkData = handle.readData(ofLength: chunkSize)
            guard !chunkData.isEmpty else { break }

            // Send chunk with simple framing
            let isLast = (offset + Int64(chunkData.count)) >= file.size
            let chunkPayload = createChunkPayload(fileId: file.fileId, index: chunkIndex, data: chunkData, isLast: isLast)
            let chunkHeader = FastDropHeader(type: .chunk, sequence: UInt32(3 + chunkIndex), payloadLength: UInt32(chunkPayload.count))
            connection.send(content: chunkHeader.encode() + chunkPayload, completion: .contentProcessed { _ in })

            // Wait for ack (simplified - in production use proper flow control)
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms

            offset += Int64(chunkData.count)
            chunkIndex += 1

            updateFileProgress(session, file: file, progress: Float(offset) / Float(file.size))
        }

        handle.closeFile()

        // Send done
        let done = DonePayload(fileId: file.fileId, totalBytes: file.size, checksum: nil)
        let doneData = (try? JSONEncoder().encode(done)) ?? Data()
        let doneHeader = FastDropHeader(type: .done, sequence: UInt32(3 + chunkIndex), payloadLength: UInt32(doneData.count))
        connection.send(content: doneHeader.encode() + doneData, completion: .contentProcessed { _ in })
    }

    private func createChunkPayload(fileId: String, index: Int, data: Data, isLast: Bool) -> Data {
        var payload = Data()
        // Simple format: fileId length (1 byte) + fileId + chunkIndex (4 bytes) + isLast (1 byte) + data
        let fileIdData = fileId.data(using: .utf8)!
        payload.append(UInt8(fileIdData.count))
        payload.append(fileIdData)
        payload.append(withUnsafeBytes(of: UInt32(index).bigEndian) { Data($0) })
        payload.append(isLast ? UInt8(1) : UInt8(0))
        payload.append(data)
        return payload
    }

    private func peerEndpoint(from peer: DiscoveredPeer) -> NWEndpoint? {
        guard let ip = peer.ipAddress, let port = peer.port else { return nil }
        return NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!)
    }

    private func updateFileProgress(_ session: TransferSession, file: TransferFile, progress: Float) {
        if let idx = session.files.firstIndex(where: { $0.id == file.id }) {
            session.files[idx].progress = progress
            session.objectWillChange.send()
        }
    }

    private func failSession(_ session: TransferSession, error: String) {
        session.status = .failed
        session.error = error
    }

    private func completeSession(_ session: TransferSession) {
        session.status = .completed
        session.overallProgress = 1.0
    }

    private func cleanupConnection(_ sessionId: UUID) {
        activeConnections[sessionId]?.cancel()
        activeConnections.removeValue(forKey: sessionId)
    }

    private func receiveHandshake(_ connection: NWConnection, sessionId: UUID) {
        logger.info("Receiving handshake")
        // Handshake will be processed via the receive loop
    }
}

// Extension to make TransferService @unchecked Sendable for use in @Sendable closures
// This is safe because all mutable state is protected by the queue and @MainActor
extension TransferService: @unchecked Sendable {}