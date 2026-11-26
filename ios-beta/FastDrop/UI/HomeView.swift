import SwiftUI
import MetalKit
import Network
import FastDropCore

// ──────────────────────────────────────────────
// Home View - Main Screen (matches HTML concept)
// ──────────────────────────────────────────────

struct HomeView: View {
    @StateObject private var discovery = DiscoveryService()
    @StateObject private var transfer = TransferService()
    @StateObject private var appState = AppState.shared

    @State private var drops: [FileDrop] = []
    @State private var ipAddress = "192.168.0.14"
    @State private var isReceiveEnabled = true
    @State private var selectedPeer: DiscoveredPeer?
    @State private var showTransferScene = false
    @State private var dragProgress: Float = 0
    @State private var toastMessage: String?
    @State private var metalView = MTKView()
    @State private var renderer: MetaballRenderer?
    @State private var hintText = "Добавьте файлы"
    @State private var hintOpacity: Double = 1.0
    @State private var chevronOffset: CGFloat = 0

    private let peers: [DiscoveredPeer] = [
        DiscoveredPeer(endpoint: NWEndpoint.hostPort(host: NWEndpoint.Host("192.168.0.14"), port: 14680), name: "Ivan's MacBook", deviceType: "Mac"),
        DiscoveredPeer(endpoint: NWEndpoint.hostPort(host: NWEndpoint.Host("192.168.0.31"), port: 14680), name: "Pixel 9", deviceType: "Android"),
        DiscoveredPeer(endpoint: NWEndpoint.hostPort(host: NWEndpoint.Host("192.168.0.52"), port: 14680), name: "Офис-ПК", deviceType: "Windows")
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                backgroundView
                    .ignoresSafeArea()

                // Metal View for Metaballs
                MetalViewRepresentable(renderer: $renderer, drops: drops)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // UI Layer
                VStack(spacing: 12) {
                    // Header
                    headerView

                    // IP & Receive toggle
                    ipSectionView

                    // Stage Area (drops + send button)
                    stageView(geometry: geo)

                    // Peer Selection Card
                    peerCardView
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 200) // Space for send button
                .opacity(1 - min(1, Double(dragProgress) * 1.8))
                .allowsHitTesting(dragProgress < 0.05)

                // Send Button (fixed at bottom center)
                VStack {
                    Spacer()
                    SendButton(
                        isEnabled: canSend,
                        onTrigger: startTransfer,
                        onDragProgress: { progress in
                            dragProgress = progress
                            hintOpacity = 1 - min(1, Double(progress) * 3)
                        }
                    )
                    .padding(.bottom, geo.safeAreaInsets.bottom + 58)
                }

                // Hint Text
                VStack {
                    Spacer()
                    Text(hintText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GlassPalette.current(for: appState.colorScheme).subtle)
                        .opacity(hintOpacity)
                        .animation(.easeOut(duration: 0.3), value: hintOpacity)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 28)
                }

                // Chevron indicator
                VStack {
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(GlassPalette.current(for: appState.colorScheme).subtle)
                        .offset(y: chevronOffset)
                        .opacity(canSend ? 1 - min(1, Double(dragProgress) * 3) : 0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: chevronOffset)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 148)
                }

                // Toast
                VStack {
                    if let toast = toastMessage {
                        Text(toast)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(GlassPalette.current(for: appState.colorScheme).glassLight)
                                    .background(.ultraThinMaterial)
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.top, geo.safeAreaInsets.top + 62)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: toastMessage)

                // Transfer Scene Overlay
                if showTransferScene {
                    TransferSceneView(
                        drops: drops,
                        onComplete: { showTransferScene = false },
                        onCancel: { showTransferScene = false }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .environment(\.colorScheme, appState.colorScheme)
            .onAppear {
                setupInitialState()
                Task { @MainActor in
                    renderer = MetaballRenderer.create(metalView: metalView)
                }
                chevronOffset = -6
            }
            .onChange(of: drops.count) { _, _ in updateHint() }
            .onChange(of: ipAddress) { _, _ in updateHint() }
        }
    }

    // ─── Computed ───
    private var canSend: Bool {
        !drops.isEmpty && isValidIP(ipAddress)
    }

    // ─── Subviews ───
    private var backgroundView: some View {
        ZStack {
            Color(appState.colorScheme == .dark ? Color(hex: "07120C") : Color(hex: "D7DFDB"))
            // Radial gradients like HTML
            RadialGradient(
                colors: [Color(hex: "30D158").opacity(0.34), .clear],
                center: .topLeading, startRadius: 0, endRadius: max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.7
            )
            RadialGradient(
                colors: [Color(hex: "14BECC").opacity(0.28), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.7
            )
            RadialGradient(
                colors: [Color(hex: "3C78FF").opacity(0.16), .clear],
                center: .topTrailing, startRadius: 0, endRadius: max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.5
            )
        }
    }

    private var headerView: some View {
        HStack {
            GlassIconButton(icon: "clock.arrow.circlepath", action: { showToast("История — только дизайн в этом демо") })
            Spacer()
            VStack(spacing: 2) {
                Text("FastDrop")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(Color(hex: "30D158"))
            }
            Spacer()
            GlassIconButton(icon: "gearshape.2", action: toggleTheme)
        }
    }

    private var ipSectionView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.system(size: 16, weight: .medium))
                Text("192.168.0.24")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: [GlassPalette.current(for: appState.colorScheme).glassLight, GlassPalette.current(for: appState.colorScheme).glassDark],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(Capsule().stroke(GlassPalette.current(for: appState.colorScheme).edge, lineWidth: 0.5))
            )

            GlassButton(
                icon: "arrow.down",
                label: isReceiveEnabled ? "↓ Приём вкл." : "↓ Приём выкл.",
                isActive: isReceiveEnabled,
                action: { isReceiveEnabled.toggle() }
            )
        }
    }

    private func stageView(geometry: GeometryProxy) -> some View {
        ZStack {
            if drops.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "30D158").opacity(0.5), Color(hex: "30D158").opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 92, height: 92)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(.white)
                        )
                    VStack(spacing: 4) {
                        Text("Добавить файлы")
                            .font(.system(size: 17, weight: .semibold))
                        Text("или перетащите их сюда")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(GlassPalette.current(for: appState.colorScheme).subtle)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .contentShape(Rectangle())
                .onTapGesture { addRandomFile() }
            } else {
                // File summary row
                HStack {
                    Text("\(drops.count) \(pluralizeFiles(drops.count)) · \(formatSize(drops.reduce(0) { $0 + $1.sizeMB }))")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [GlassPalette.current(for: appState.colorScheme).glassLight, GlassPalette.current(for: appState.colorScheme).glassDark],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .overlay(Capsule().stroke(GlassPalette.current(for: appState.colorScheme).edge, lineWidth: 0.5))
                        )
                    Spacer()
                    Button(action: addRandomFile) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [GlassPalette.current(for: appState.colorScheme).glassLight, GlassPalette.current(for: appState.colorScheme).glassDark],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .overlay(Circle().stroke(GlassPalette.current(for: appState.colorScheme).edge, lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var peerCardView: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Text("ПОЛУЧАТЕЛЬ")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GlassPalette.current(for: appState.colorScheme).subtle)
                        .textCase(.uppercase)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: "30D158")).frame(width: 6, height: 6)
                            .opacity(0.3 + 0.7 * sin(Date().timeIntervalSince1970 * 2))
                        Text("Готов")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: "30D158"))
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(peers) { peer in
                            PeerChip(
                                peer: peer,
                                isSelected: selectedPeer?.id == peer.id,
                                action: {
                                    selectedPeer = peer
                                    ipAddress = peer.ipAddress ?? ""
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }

                GlassTextField(
                    text: $ipAddress,
                    placeholder: "192.168.0.14",
                    leadingIcon: "network",
                    isError: !ipAddress.isEmpty && !isValidIP(ipAddress)
                )
            }
        }
    }

    // ─── Actions ───
    private func setupInitialState() {
        drops = FileDrop.randomDrops(count: 3, in: UIScreen.main.bounds)
        selectedPeer = peers[0]
        ipAddress = peers[0].ipAddress ?? ""
        // Stagger appearance
        for (i, drop) in drops.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    // drop appears
                }
            }
        }
    }

    private func addRandomFile() {
        guard drops.count < 8 else { showToast("В демо — не больше 8 капель"); return }
        let newDrops = FileDrop.randomDrops(count: 1, in: UIScreen.main.bounds)
        drops.append(newDrops[0])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func startTransfer() {
        guard canSend else { return }
        showTransferScene = true
        // Prepare drops for transfer scene
        for i in drops.indices {
            drops[i].state = .wait
        }
    }

    private func updateHint() {
        if drops.isEmpty {
            hintText = "Добавьте файлы"
        } else if !isValidIP(ipAddress) {
            hintText = "Выберите получателя"
        } else {
            hintText = "Потяните к центру, чтобы отправить"
        }
    }

    private func isValidIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part), num >= 0, num <= 255 else { return false }
            return true
        }
    }

    private func toggleTheme() {
        withAnimation(.easeInOut(duration: 0.3)) {
            appState.colorScheme = appState.colorScheme == .dark ? .light : .dark
        }
        showToast("Тема: \(appState.colorScheme == .dark ? "тёмная" : "светлая")")
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                toastMessage = nil
            }
        }
    }
}

// ──────────────────────────────────────────────
// Metal View Representable
// ──────────────────────────────────────────────

struct MetalViewRepresentable: UIViewRepresentable {
    @Binding var renderer: MetaballRenderer?
    let drops: [FileDrop]

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.framebufferOnly = true
        view.isPaused = false
        view.preferredFramesPerSecond = 120

        // Create renderer on main actor
        Task { @MainActor in
            renderer = MetaballRenderer.create(metalView: view)
        }

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Convert FileDrop to MetaballData
        let metalBalls = drops.map { drop in
            MetaballData(
                pos: SIMD2<Float>(Float(drop.pos.x), Float(drop.pos.y)),
                vel: SIMD2<Float>(Float(drop.vel.dx), Float(drop.vel.dy)),
                radius: Float(drop.radius),
                stretch: Float(drop.stretch),
                phase: Float(drop.phase)
            )
        }
        renderer?.updateBalls(metalBalls)
        renderer?.updateViewport(uiView.bounds.size, scale: uiView.contentScaleFactor)
    }
}

// ──────────────────────────────────────────────
// Preview
// ──────────────────────────────────────────────

#Preview {
    HomeView()
}