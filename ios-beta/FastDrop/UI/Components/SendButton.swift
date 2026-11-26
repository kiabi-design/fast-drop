import SwiftUI
import Combine

// ──────────────────────────────────────────────
// Send Button with Drag-to-Send Gesture
// Matches HTML concept: spring physics, haptics, threshold trigger
// ──────────────────────────────────────────────

struct SendButton: View {
    let isEnabled: Bool
    let onTrigger: () -> Void
    let onDragProgress: (Float) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var dragStartLocation: CGPoint = .zero
    @State private var hasTriggered = false
    @State private var ripplePhase: CGFloat = 0

    // Spring physics constants (match HTML: k=170, c=16)
    private let springStiffness: CGFloat = 170
    private let springDamping: CGFloat = 16
    private let triggerThreshold: Float = 0.96
    private let returnThreshold: Float = 0.78

    var body: some View {
        ZStack {
            // Ripple ring (pulsing when idle)
            Circle()
                .stroke(Color(hex: "30D158"), lineWidth: 2)
                .frame(width: 84, height: 84)
                .scaleEffect(1 + 0.3 * sin(ripplePhase))
                .opacity(isEnabled && !isDragging ? 0.5 + 0.3 * sin(ripplePhase) : 0)
                .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: false), value: ripplePhase)

            // Main button
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "30D158").opacity(0.82), Color(hex: "14A03C").opacity(0.45)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "arrow.up")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-8))
                )
                .scaleEffect(isDragging ? 1.1 : 1.0)
                .shadow(color: Color(hex: "30D158").opacity(0.4), radius: 20, x: 0, y: 10)
        }
        .offset(dragOffset)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isEnabled else { return }

                    if !isDragging {
                        isDragging = true
                        dragStartLocation = value.location
                        hasTriggered = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                    let translation = CGSize(
                        width: value.location.x - dragStartLocation.x,
                        height: value.location.y - dragStartLocation.y
                    )

                    // Calculate progress toward center (simplified - assume center is at screen center)
                    // In real app, this would be calculated relative to the view geometry
                    let progress = calculateProgress(translation: translation)

                    onDragProgress(progress)

                    // Apply spring factor based on progress
                    let factor: CGFloat = progress > 0.5 ? 1.0 : 0.12
                    dragOffset = CGSize(width: translation.width * factor, height: translation.height * factor)

                    // Haptic at halfway
                    if progress > 0.5 && !hasTriggered {
                        hasTriggered = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }

                    // Auto-trigger at threshold
                    if progress >= triggerThreshold && !hasTriggered {
                        hasTriggered = true
                        trigger()
                    }
                }
                .onEnded { value in
                    guard isEnabled else { return }
                    isDragging = false

                    let translation = CGSize(
                        width: value.location.x - dragStartLocation.x,
                        height: value.location.y - dragStartLocation.y
                    )
                    let progress = calculateProgress(translation: translation)

                    if progress >= returnThreshold {
                        trigger()
                    } else {
                        springBack()
                    }
                }
        )
        .onAppear {
            ripplePhase = .pi * 2
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dragOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isDragging)
    }

    private func calculateProgress(translation: CGSize) -> Float {
        // Simplified: distance from start toward center
        // Real implementation would use GeometryReader for accurate center
        let distance = hypot(translation.width, translation.height)
        let maxDistance: CGFloat = 200 // approximate
        return Float(min(1.0, distance / maxDistance))
    }

    private func trigger() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // Triple haptic like HTML: [20, 30, 20]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        onTrigger()
    }

    private func springBack() {
        dragOffset = .zero
        onDragProgress(0)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// ──────────────────────────────────────────────
// Preview
// ──────────────────────────────────────────────

#Preview {
    VStack(spacing: 40) {
        SendButton(isEnabled: true, onTrigger: { print("Trigger!") }, onDragProgress: { _ in })
        SendButton(isEnabled: false, onTrigger: {}, onDragProgress: { _ in })
    }
    .padding()
    .background(Color(hex: "E9F1EC"))
}