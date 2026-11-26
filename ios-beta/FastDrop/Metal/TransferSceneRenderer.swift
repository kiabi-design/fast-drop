@preconcurrency import MetalKit
import SwiftUI

// ──────────────────────────────────────────────
// Transfer Scene Renderer (rings, black hole, ripple)
// ──────────────────────────────────────────────

public struct TransferRing {
    public var center: SIMD2<Float>   // normalized 0..1
    public var maxRadius: Float       // normalized
    public var progress: Float        // 0..1
    public var isActive: Bool

    public init(center: SIMD2<Float>, maxRadius: Float, progress: Float, isActive: Bool) {
        self.center = center
        self.maxRadius = maxRadius
        self.progress = progress
        self.isActive = isActive
    }
}

public struct BlackHoleState {
    public var radius: Float          // normalized
    public var pulse: Float           // phase

    public init(radius: Float, pulse: Float) {
        self.radius = radius
        self.pulse = pulse
    }
}

// TransferSceneRenderer is non-isolated because MTKViewDelegate methods run on the render thread
public final class TransferSceneRenderer: NSObject, MTKViewDelegate {
    // ─── Metal resources (nonisolated - accessed from render thread) ───
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    nonisolated(unsafe) private var pipelineState: MTLRenderPipelineState!
    nonisolated(unsafe) private var uniformsBuffer: MTLBuffer!

    // ─── State (nonisolated - accessed from render thread) ───
    nonisolated(unsafe) private var rings: [TransferRing] = []
    nonisolated(unsafe) private var blackHole = BlackHoleState(radius: 0.0, pulse: 0.0)
    nonisolated(unsafe) private var overallProgress: Float = 0.0
    nonisolated(unsafe) private var viewportSize: CGSize = .zero
    nonisolated(unsafe) private var pixelRatio: Float = 1.0
    nonisolated(unsafe) private var lastTime: CFTimeInterval = 0
    private let center = SIMD2<Float>(0.5, 0.5)

    // Private init - use create() factory method
    private init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = queue
        super.init()
        createPipeline()
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<TransferUniforms>.stride, options: .storageModeShared)
    }

    // Factory method to create and configure on @MainActor
    @MainActor
    public static func create(metalView: MTKView) -> TransferSceneRenderer? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        let renderer = TransferSceneRenderer(device: device, queue: queue)

        metalView.device = device
        metalView.delegate = renderer
        metalView.preferredFramesPerSecond = 120
        metalView.framebufferOnly = true
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.isPaused = false

        return renderer
    }

    // ─── Pipeline ───
    private func createPipeline() {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "vertexMain"),
              let fragmentFn = library.makeFunction(name: "transferFragment") else {
            fatalError("Failed to load transfer shader functions")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipelineState = try! device.makeRenderPipelineState(descriptor: desc)
    }

    // ─── Public API (@MainActor for SwiftUI) ───
    @MainActor
    func startTransfer(ringCount: Int, viewportSize: CGSize) {
        self.viewportSize = viewportSize
        rings = (0..<min(ringCount, 8)).map { i in
            let angle = Float(i) * 2 * .pi / Float(ringCount)
            let r = Float(0.15 + 0.05 * sin(Float(i)))
            return TransferRing(
                center: SIMD2<Float>(0.5 + 0.3 * cos(angle), 0.5 + 0.3 * sin(angle)),
                maxRadius: r,
                progress: 0.0,
                isActive: true
            )
        }
        blackHole = BlackHoleState(radius: 0.08, pulse: 0.0)
        overallProgress = 0.0
    }

    @MainActor
    func updateRingProgress(index: Int, progress: Float) {
        guard index < rings.count else { return }
        rings[index].progress = progress
    }

    @MainActor
    func setRingInactive(index: Int) {
        guard index < rings.count else { return }
        rings[index].isActive = false
    }

    @MainActor
    func updateBlackHole(radius: Float, pulse: Float) {
        blackHole.radius = radius
        blackHole.pulse = pulse
    }

    @MainActor
    public func setOverallProgress(_ p: Float) {
        overallProgress = p
    }

    @MainActor
    public func updateViewport(_ size: CGSize, scale: CGFloat) {
        viewportSize = size
        pixelRatio = Float(scale)
    }

    // ─── MTKViewDelegate (@MainActor - runs on main thread in Swift 6) ───
    @MainActor
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        pixelRatio = Float(view.contentScaleFactor)
    }

    @MainActor
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }

        let now = CACurrentMediaTime()
        _ = lastTime > 0 ? now - lastTime : 1/60
        lastTime = now

        updateUniforms(time: Float(now))

        let cmdBuffer = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    private func updateUniforms(time: Float) {
        var ringProgress: (Float, Float, Float, Float, Float, Float, Float, Float) = (0,0,0,0,0,0,0,0)
        var ringCenter: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>,
                         SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = (SIMD2<Float>(0,0), SIMD2<Float>(0,0), SIMD2<Float>(0,0), SIMD2<Float>(0,0),
                                                                                     SIMD2<Float>(0,0), SIMD2<Float>(0,0), SIMD2<Float>(0,0), SIMD2<Float>(0,0))
        var ringRadius: (Float, Float, Float, Float, Float, Float, Float, Float) = (0,0,0,0,0,0,0,0)

        for (i, ring) in rings.enumerated() where i < 8 {
            switch i {
            case 0: ringProgress.0 = ring.progress; ringCenter.0 = ring.center; ringRadius.0 = ring.maxRadius
            case 1: ringProgress.1 = ring.progress; ringCenter.1 = ring.center; ringRadius.1 = ring.maxRadius
            case 2: ringProgress.2 = ring.progress; ringCenter.2 = ring.center; ringRadius.2 = ring.maxRadius
            case 3: ringProgress.3 = ring.progress; ringCenter.3 = ring.center; ringRadius.3 = ring.maxRadius
            case 4: ringProgress.4 = ring.progress; ringCenter.4 = ring.center; ringRadius.4 = ring.maxRadius
            case 5: ringProgress.5 = ring.progress; ringCenter.5 = ring.center; ringRadius.5 = ring.maxRadius
            case 6: ringProgress.6 = ring.progress; ringCenter.6 = ring.center; ringRadius.6 = ring.maxRadius
            case 7: ringProgress.7 = ring.progress; ringCenter.7 = ring.center; ringRadius.7 = ring.maxRadius
            default: break
            }
        }

        var u = TransferUniforms(
            time: time,
            center: center,
            progress: overallProgress,
            ringCount: UInt32(rings.filter { $0.isActive }.count),
            ringProgress: ringProgress,
            ringCenter: ringCenter,
            ringRadius: ringRadius,
            blackHoleRadius: blackHole.radius,
            blackHolePulse: blackHole.pulse
        )

        memcpy(uniformsBuffer.contents(), &u, MemoryLayout<TransferUniforms>.stride)
    }
}

// ──────────────────────────────────────────────
// Transfer Uniforms (matches Metal)
// ──────────────────────────────────────────────

public struct TransferUniforms {
    public var time: Float
    public var center: SIMD2<Float>
    public var progress: Float
    public var ringCount: UInt32
    public var ringProgress: (Float, Float, Float, Float, Float, Float, Float, Float)
    public var ringCenter: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>,
                     SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    public var ringRadius: (Float, Float, Float, Float, Float, Float, Float, Float)
    public var blackHoleRadius: Float
    public var blackHolePulse: Float
    public var _pad: (Float, Float)

    public init(time: Float, center: SIMD2<Float>, progress: Float, ringCount: UInt32,
                ringProgress: (Float, Float, Float, Float, Float, Float, Float, Float),
                ringCenter: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>,
                            SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>),
                ringRadius: (Float, Float, Float, Float, Float, Float, Float, Float),
                blackHoleRadius: Float, blackHolePulse: Float) {
        self.time = time
        self.center = center
        self.progress = progress
        self.ringCount = ringCount
        self.ringProgress = ringProgress
        self.ringCenter = ringCenter
        self.ringRadius = ringRadius
        self.blackHoleRadius = blackHoleRadius
        self.blackHolePulse = blackHolePulse
        self._pad = (0, 0)
    }
}