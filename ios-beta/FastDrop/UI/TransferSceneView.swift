import SwiftUI
import MetalKit
import FastDropCore

// ──────────────────────────────────────────────
// Transfer Scene View (Black Hole Animation)
// Matches HTML concept: scatter → ring → pull → gone
// ──────────────────────────────────────────────

struct TransferSceneView: View {
    let drops: [FileDrop]
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var showStats = false
    @State private var overallProgress: Float = 0
    @State private var currentFileIndex = 0
    @State private var ringProgress: [Float] = []
    @State private var blackHoleRadius: Float = 0.08
    @State private var blackHolePulse: Float = 0
    @State private var metalView = MTKView()
    @State private var renderer: TransferSceneRenderer?
    @State private var transferStartTime = Date()
    @State private var speeds: [Double] = []
    @State private var currentSpeed: Double = 0
    @State private var transferredBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var phase = "Отправка"

    private let files: [FileDrop]

    init(drops: [FileDrop], onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.drops = drops
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.files = drops
        self._ringProgress = State(initialValue: Array(repeating: 0, count: drops.count))
        self._totalBytes = State(initialValue: Int64(drops.reduce(0) { $0 + Int64($1.sizeMB * 1_048_576) }))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full-screen black background with Metal overlay
                Color.black.ignoresSafeArea()

                // Metal View for transfer scene
                TransferMetalView(renderer: $renderer, ringProgress: ringProgress, blackHoleRadius: blackHoleRadius, blackHolePulse: blackHolePulse)
                    .ignoresSafeArea()

                // UI Overlay
                VStack {
                    // Top status chip
                    HStack {
                        Text(phase)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                                    .background(.ultraThinMaterial)
                            )
                        Spacer()
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(Color.white.opacity(0.1)).background(.ultraThinMaterial)
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, geo.safeAreaInsets.top + 12)

                    Spacer()

                    // Center file info
                    VStack(spacing: 8) {
                        if currentFileIndex < files.count {
                            Text(files[currentFileIndex].name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("Отправка на \(files.first?.name ?? "устройство")...")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // Stats
                    if showStats {
                        HStack(spacing: 0) {
                            statBox(label: "Осталось", value: formatTimeRemaining())
                            Divider().frame(height: 40).background(Color.white.opacity(0.2))
                            statBox(label: "Передано", value: formatSizeMB(transferredBytes))
                            Divider().frame(height: 40).background(Color.white.opacity(0.2))
                            statBox(label: "Всего", value: formatSizeMB(totalBytes))
                        }
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.white.opacity(0.05))
                                .background(.ultraThinMaterial)
                        )
                        .padding(.horizontal, 40)
                    }

                    Spacer()

                    // Bottom actions
                    VStack(spacing: 12) {
                        if overallProgress >= 1.0 {
                            HStack(spacing: 12) {
                                GlassButton(icon: "plus", label: "+ Ещё", action: {
                                    onComplete()
                                })
                                GlassButton(icon: "checkmark", label: "Готово", isActive: true, action: {
                                    onComplete()
                                })
                            }
                            .padding(.horizontal, 40)
                        } else {
                            GlassButton(icon: "xmark", label: "Отменить", isDanger: true, action: onCancel)
                                .frame(maxWidth: 200)
                        }
                    }
                    .padding(.bottom, geo.safeAreaInsets.bottom + 16)
                }
            }
            .statusBarHidden()
            .onAppear {
                setupTransferScene(geometry: geo)
                startAnimation()
            }
        }
    }

    private func statBox(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private func setupTransferScene(geometry: GeometryProxy) {
        renderer = TransferSceneRenderer.create(metalView: metalView)
        renderer?.startTransfer(ringCount: files.count, viewportSize: geometry.size)
        metalView.contentScaleFactor = UIScreen.main.scale
    }

    private func startAnimation() {
        // Scatter phase - immediate
        // Ring phase - sequential
        // Pull phase - sequential after ring
        animateRings()
    }

    private func animateRings() {
        let ringDuration: Double = 1.2
        let pullDuration: Double = 1.5
        let delayBetweenRings: Double = 0.45

        for i in 0..<files.count {
            let ringDelay = Double(i) * delayBetweenRings + 1.1 // wait 1.1s before first ring

            // Ring animation
            DispatchQueue.main.asyncAfter(deadline: .now() + ringDelay) {
                guard i < ringProgress.count else { return }
                withAnimation(.easeInOut(duration: ringDuration)) {
                    ringProgress[i] = 1.0
                }
                currentFileIndex = i
                phase = "Отправка \(i + 1) из \(files.count)"
            }

            // Pull animation (starts after ring + 0.35s)
            DispatchQueue.main.asyncAfter(deadline: .now() + ringDelay + ringDuration + 0.35) {
                withAnimation(.easeInOut(duration: pullDuration)) {
                    // Black hole grows
                    blackHoleRadius = 0.3
                }
                // Simulate transfer progress
                simulateTransfer(for: i, duration: pullDuration)
            }
        }

        // Complete after all
        let totalDuration = Double(files.count) * delayBetweenRings + 1.1 + ringDuration + pullDuration + 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            completeTransfer()
        }
    }

    private func simulateTransfer(for index: Int, duration: Double) {
        let fileSize = Int64(files[index].sizeMB * 1_048_576)
        let steps = 30
        let stepDuration = duration / Double(steps)

        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * stepDuration) {
                let progress = Float(step) / Float(steps)
                let bytes = Int64(Float(fileSize) * progress)
                transferredBytes += bytes - (step > 1 ? Int64(Float(fileSize) * Float(step - 1) / Float(steps)) : 0)

                // Simulate speed
                let baseSpeed = 18.0 // MB/s
                let variation = 14.0 * sin(Date().timeIntervalSince1970 * 1.3) + 6.0 * sin(Date().timeIntervalSince1970 * 3.7)
                currentSpeed = max(0.1, baseSpeed + variation)
                speeds.append(currentSpeed)

                overallProgress = Float(transferredBytes) / Float(totalBytes)
            }
        }
    }

    private func completeTransfer() {
        overallProgress = 1.0
        phase = "Готово"
        showStats = true

        // Final stats
        let avgSpeed = speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count)
        let maxSpeed = speeds.max() ?? 0
        let minSpeed = speeds.min() ?? 0

        // Haptic success
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func formatTimeRemaining() -> String {
        guard overallProgress > 0, overallProgress < 1 else { return "—" }
        let elapsed = Date().timeIntervalSince(transferStartTime)
        let totalEstimated = elapsed / Double(overallProgress)
        let remaining = totalEstimated - elapsed
        if remaining < 60 { return "\(Int(remaining)) с" }
        return String(format: "%d:%02d", Int(remaining / 60), Int(remaining) % 60)
    }

    private func formatSizeMB(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f МБ", mb).replacingOccurrences(of: ".", with: ",")
    }
}

// ──────────────────────────────────────────────
// Transfer Metal View
// ──────────────────────────────────────────────

struct TransferMetalView: UIViewRepresentable {
    @Binding var renderer: TransferSceneRenderer?
    let ringProgress: [Float]
    let blackHoleRadius: Float
    let blackHolePulse: Float

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.framebufferOnly = true
        view.isPaused = false
        view.preferredFramesPerSecond = 120
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        for (i, progress) in ringProgress.enumerated() {
            renderer?.updateRingProgress(index: i, progress: progress)
        }
        renderer?.updateBlackHole(radius: blackHoleRadius, pulse: blackHolePulse)
        renderer?.setOverallProgress(ringProgress.reduce(0, +) / Float(max(1, ringProgress.count)))
        renderer?.updateViewport(uiView.bounds.size, scale: uiView.contentScaleFactor)
    }
}

// ──────────────────────────────────────────────
// Preview
// ──────────────────────────────────────────────

#Preview {
    TransferSceneView(
        drops: FileDrop.randomDrops(count: 3, in: UIScreen.main.bounds),
        onComplete: {},
        onCancel: {}
    )
}