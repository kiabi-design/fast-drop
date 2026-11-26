import Foundation
import Network
import Combine

// ──────────────────────────────────────────────
// Discovery Service (Bonjour / mDNS)
// ──────────────────────────────────────────────

@MainActor
public final class DiscoveryService: ObservableObject {
    @Published public private(set) var peers: [DiscoveredPeer] = []
    @Published public private(set) var isScanning = false
    @Published public var error: String?

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "fastdrop.discovery", qos: .userInitiated)
    private let parameters: NWParameters

    public init() {
        // Use TCP with Bonjour
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10
        self.parameters = NWParameters(tls: nil, tcp: tcpOptions)
        self.parameters.includePeerToPeer = true
    }

    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        error = nil

        let desc = NWBrowser.Descriptor.bonjour(type: kServiceType, domain: nil)
        browser = NWBrowser(for: desc, using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.error = nil
                case .failed(let err):
                    self?.error = "Discovery failed: \(err.localizedDescription)"
                    self?.isScanning = false
                case .cancelled:
                    self?.isScanning = false
                default: break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.processResults(results)
            }
        }

        browser?.start(queue: queue)
    }

    public func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    private func processResults(_ results: Set<NWBrowser.Result>) {
        var newPeers: [DiscoveredPeer] = []

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }

            let peer = DiscoveredPeer(
                endpoint: result.endpoint,
                name: name,
                deviceType: "Unknown"
            )

            // Try to resolve IP
            resolveEndpoint(result.endpoint) { [weak self] ip, port in
                Task { @MainActor in
                    peer.ipAddress = ip
                    peer.port = port
                    self?.updatePeer(peer)
                }
            }

            newPeers.append(peer)
        }

        // Merge with existing, preserve lastSeen
        var merged: [DiscoveredPeer] = []
        for new in newPeers {
            if let existing = peers.first(where: { $0.endpoint == new.endpoint }) {
                // Preserve lastSeen from existing peer
                new.lastSeen = existing.lastSeen
                merged.append(new)
            } else {
                merged.append(new)
            }
        }

        // Remove stale (>30s)
        let now = Date()
        peers = merged.filter { now.timeIntervalSince($0.lastSeen) < 30 }
    }

    private func updatePeer(_ peer: DiscoveredPeer) {
        if let idx = peers.firstIndex(where: { $0.endpoint == peer.endpoint }) {
            peers[idx] = peer
        }
    }

    // Use @Sendable for the completion closure
    private func resolveEndpoint(_ endpoint: NWEndpoint, completion: @escaping @Sendable (String?, UInt16?) -> Void) {
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                    let ip = "\(host)"
                    completion(ip, port.rawValue)
                } else {
                    completion(nil, nil)
                }
                connection.cancel()
            case .failed, .cancelled:
                completion(nil, nil)
            default: break
            }
        }
        connection.start(queue: queue)
    }
}