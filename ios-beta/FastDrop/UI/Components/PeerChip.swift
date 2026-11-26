import SwiftUI

// ──────────────────────────────────────────────
// Peer Chip Component
// ──────────────────────────────────────────────

struct PeerChip: View {
    let peer: DiscoveredPeer
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(deviceIcon(for: peer.deviceType))
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 0) {
                    Text(peer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GlassPalette.current(for: scheme).fg)
                    if let ip = peer.ipAddress {
                        Text(ip)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(GlassPalette.current(for: scheme).subtle)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, isSelected ? 14 : 10)
            .padding(.trailing, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color(hex: "30D158").opacity(0.28) : Color(hex: "7F7F7F").opacity(0.14))
                    .overlay(Capsule().stroke(isSelected ? Color(hex: "30D158") : .clear, lineWidth: 1.5))
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func deviceIcon(for type: String) -> String {
        switch type.lowercased() {
        case "iphone", "ios": return "📱"
        case "ipad": return "📱"
        case "mac", "macbook", "macos": return "💻"
        default: return "🖥"
        }
    }
}