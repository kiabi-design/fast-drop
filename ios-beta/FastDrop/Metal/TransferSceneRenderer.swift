import MetalKit
import SwiftUI

// ──────────────────────────────────────────────
// Transfer Scene Renderer (rings, black hole, ripple)
// ──────────────────────────────────────────────

struct TransferRing {
    var center: SIMD2<Float>   // normalized 0..1
    var maxRadius: Float       // normalized
    var progress: Float        // 0..1
    var isActive: Bool
}

struct BlackHoleState {
    var radius: Float          // normalized
    var pulse: Float           // phase
}

final class TransferSceneRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var uniformsBuffer: MTLBuffer!

    private var rings: [TransferRing] = []
    private var blackHole = BlackHoleState(radius: 0.0, pulse: 0.0)
    private var overallProgress: Float = 0.0
    private var viewportSize: CGSize = .zero
    private var pixelRatio: Float = 1.0
    private var lastTime: CFTimeInterval = 0
    private let center = SIMD2<Float>(0.5, 0.5)

    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()

        metalView.device = device
        metalView.delegate = self
        metalView.preferredFramesPerSecond = 120
        metalView.framebufferOnly = true
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.isPaused = false

        createPipeline(metalView: metalView)
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<TransferUniforms>.stride, options: .storageModeShared)
    }

    private func createPipeline(metalView: MTKView) {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "vertexMain"),
              let fragmentFn = library.makeFunction(name: "transferFragment") else {
            fatalError("Failed to load transfer shader functions")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pipelineState = try! device.makeRenderPipelineState(descriptor: desc)
    }

    // ─── Public API ───
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

    func updateRingProgress(index: Int, progress: Float) {
        guard index < rings.count else { return }
        rings[index].progress = progress
    }

    func setRingInactive(index: Int) {
        guard index < rings.count else { return }
        rings[index].isActive = false
    }

    func updateBlackHole(radius: Float, pulse: Float) {
        blackHole.radius = radius
        blackHole.pulse = pulse
    }

    func setOverallProgress(_ p: Float) {
        overallProgress = p
    }

    func updateViewport(_ size: CGSize, scale: CGFloat) {
        viewportSize = size
        pixelRatio = Float(scale)
    }

    // ─── MTKViewDelegate ───
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateViewport(size, scale: view.contentScaleFactor)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }

        let now = CACurrentMediaTime()
        let dt = lastTime > 0 ? now - lastTime : 1/60
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
        var u = TransferUniforms(
            time: time,
            center: center,
            progress: overallProgress,
            ringCount: UInt32(rings.filter { $0.isActive }.count),
            ringProgress: (0,0,0,0,0,0,0,0),
            ringCenter: (SIMD2<Float>(0,0), SIMD2<Float>(0,0), SIMD2<Float>(0,0), SIMD2<Float>(0,0),
                         SIMD2<Float>(0,0), SIMD2<Float>(0,0), SIMD2<Float>(0,0), SIMD2<Float>(0,0)),
            ringRadius: (0,0,0,0,0,0,0,0),
            blackHoleRadius: blackHole.radius,
            blackHolePulse: blackHole.pulse,
            _pad: (0,0)
        )

        for (i, ring) in rings.enumerated() where i < 8 {
            u.ringProgress.(i) = ring.progress
            u.ringCenter.(i) = ring.center
            u.ringRadius.(i) = ring.maxRadius
        }

        memcpy(uniformsBuffer.contents(), &u, MemoryLayout<TransferUniforms>.stride)
    }
}

// ──────────────────────────────────────────────
// Transfer Uniforms (matches Metal)
// ──────────────────────────────────────────────

struct TransferUniforms {
    var time: Float
    var center: SIMD2<Float>
    var progress: Float
    var ringCount: UInt32
    var ringProgress: (Float, Float, Float, Float, Float, Float, Float, Float)
    var ringCenter: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>,
                     SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    var ringRadius: (Float, Float, Float, Float, Float, Float, Float, Float)
    var blackHoleRadius: Float
    var blackHolePulse: Float
    var _pad: (Float, Float)
}