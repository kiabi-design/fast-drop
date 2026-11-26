import SwiftUI

// ──────────────────────────────────────────────
// Glass Palette (matches Flutter liquid_glass.dart)
// ──────────────────────────────────────────────

struct GlassPalette {
    let fg: Color
    let subtle: Color
    let accent: Color
    let danger: Color
    let success: Color
    let glassLight: Color
    let glassDark: Color
    let edge: Color
    let shadow: Color

    static let light = GlassPalette(
        fg: Color(hex: "0B0B12"),
        subtle: Color(hex: "3C3C43").opacity(0.62),
        accent: Color(hex: "30D158"),
        danger: Color(hex: "FF453A"),
        success: Color(hex: "30D158"),
        glassLight: Color.white.opacity(0.66),
        glassDark: Color.white.opacity(0.26),
        edge: Color.white.opacity(0.9),
        shadow: Color(hex: "1E502D").opacity(0.2)
    )

    static let dark = GlassPalette(
        fg: .white,
        subtle: Color(hex: "EBEBF5").opacity(0.6),
        accent: Color(hex: "30D158"),
        danger: Color(hex: "FF453A"),
        success: Color(hex: "30D158"),
        glassLight: Color.white.opacity(0.17),
        glassDark: Color.white.opacity(0.05),
        edge: Color.white.opacity(0.36),
        shadow: Color.black.opacity(0.55)
    )

    static func current(for scheme: ColorScheme) -> GlassPalette {
        scheme == .dark ? .dark : .light
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// ──────────────────────────────────────────────
// Glass View Modifiers
// ──────────────────────────────────────────────

struct GlassBackground: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var cornerRadius: CGFloat = 30
    var blur: CGFloat = 22
    var saturation: CGFloat = 1.8
    var borderWidth: CGFloat = 0.5

    func body(content: Content) -> some View {
        let palette = GlassPalette.current(for: scheme)
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [palette.glassLight, palette.glassDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(palette.edge, lineWidth: borderWidth)
                    )
                    .shadow(color: palette.shadow, radius: 10, x: 0, y: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [palette.edge.opacity(0.4), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 1
                            )
                    )
            )
    }
}

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GlassButton: View {
    let icon: String?
    let label: String
    var isActive: Bool = false
    var isDanger: Bool = false
    var action: () -> Void

    @Environment(\.colorScheme) var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isDanger ? Color(hex: "FF6B62") : (isActive ? .white : GlassPalette.current(for: scheme).fg))
            .padding(.vertical, 9)
            .padding(.horizontal, 15)
            .background(
                Capsule()
                    .fill(isActive ?
                        LinearGradient(colors: [Color(hex: "30D158").opacity(0.95), Color(hex: "14A03C").opacity(0.7)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [GlassPalette.current(for: scheme).glassLight, GlassPalette.current(for: scheme).glassDark],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isActive ? Color(hex: "30D158") : GlassPalette.current(for: scheme).edge, lineWidth: isActive ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct GlassIconButton: View {
    let icon: String
    var size: CGFloat = 44
    var action: () -> Void
    @Environment(\.colorScheme) var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .medium))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [GlassPalette.current(for: scheme).glassLight, GlassPalette.current(for: scheme).glassDark],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().stroke(GlassPalette.current(for: scheme).edge, lineWidth: 0.5))
                )
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
    }
}

struct GlassChip: View {
    let icon: String
    let title: String
    let subtitle: String?
    var isSelected: Bool = false
    var action: () -> Void
    @Environment(\.colorScheme) var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(icon)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let subtitle = subtitle {
                        Text(subtitle)
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
}

struct GlassTextField: View {
    @Binding var text: String
    let placeholder: String
    let leadingIcon: String?
    var isError: Bool = false
    @Environment(\.colorScheme) var scheme

    var body: some View {
        HStack(spacing: 10) {
            if let icon = leadingIcon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(GlassPalette.current(for: scheme).subtle)
            }
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(GlassPalette.current(for: scheme).fg)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(hex: "7F7F7F").opacity(0.14))
                .overlay(
                    Capsule()
                        .stroke(isError ? Color(hex: "FF453A") : GlassPalette.current(for: scheme).edge.opacity(0), lineWidth: isError ? 1.5 : 0)
                )
        )
    }
}

struct GlassProgressBar: View {
    let progress: Float
    var height: CGFloat = 6
    @Environment(\.colorScheme) var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: "7F7F7F").opacity(0.14))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "30D158"), Color(hex: "14A03C")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(progress))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 30
    @Environment(\.colorScheme) var scheme

    init(padding: CGFloat = 16, cornerRadius: CGFloat = 30, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(LinearGradient(
                        colors: [GlassPalette.current(for: scheme).glassLight, GlassPalette.current(for: scheme).glassDark],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(GlassPalette.current(for: scheme).edge, lineWidth: 0.5)
                    )
                    .shadow(color: GlassPalette.current(for: scheme).shadow, radius: 10, x: 0, y: 10)
            )
    }
}

// ──────────────────────────────────────────────
// View Extensions
// ──────────────────────────────────────────────

extension View {
    func glassBackground(cornerRadius: CGFloat = 30) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    func pressable(scale: CGFloat = 0.93) -> some View {
        buttonStyle(PressableButtonStyle(scale: scale))
    }
}