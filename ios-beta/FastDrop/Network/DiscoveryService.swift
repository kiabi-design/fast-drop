import Foundation
import Network
import Combine

// ──────────────────────────────────────────────
// Discovery Service (Bonjour / mDNS)
// ──────────────────────────────────────────────

@MainActor
final class DiscoveryService: ObservableObject {
    @Published private(set) var peers: [DiscoveredPeer] = []
    @Published private(set) var isScanning = false
    @Published var error: String?

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "fastdrop.discovery", qos: .userInitiated)
    private let parameters: NWParameters
    private var cancellables = Set<AnyCancellable>()

    override init() {
        // Use TCP with Bonjour
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10
        self.parameters = NWParameters(tls: nil, tcp: tcpOptions)
        self.parameters.includePeerToPeer = true
        super.init()
    }

    func startScanning() {
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

    func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    private func processResults(_ results: Set<NWBrowser.Result>) {
        var newPeers: [DiscoveredPeer] = []

        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }

            var peer = DiscoveredPeer(
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
                var updated = new
                updated.lastSeen = existing.lastSeen
                merged.append(updated)
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

    private func resolveEndpoint(_ endpoint: NWEndpoint, completion: @escaping (String?, UInt16?) -> Void) {
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