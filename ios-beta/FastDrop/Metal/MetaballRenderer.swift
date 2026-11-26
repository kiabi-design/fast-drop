import MetalKit
import SwiftUI
import Combine

// ──────────────────────────────────────────────
// Metaball data (matches Metal struct)
// ──────────────────────────────────────────────

struct MetaballData {
    var pos: SIMD2<Float>      // normalized 0..1
    var vel: SIMD2<Float>      // normalized velocity
    var radius: Float          // base radius in points
    var stretch: Float         // 0..0.55
    var phase: Float           // idle wobble
}

final class MetaballRenderer: NSObject, MTKViewDelegate {
    // ─── Metal resources ───
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var uniformsBuffer: MTLBuffer!
    private var ballsBuffer: MTLBuffer!

    // ─── State ───
    private var balls: [MetaballData] = []
    private var viewportSize: CGSize = .zero
    private var pixelRatio: Float = 1.0
    private var lastTime: CFTimeInterval = 0
    private let maxBalls = 32

    // ─── Published for SwiftUI ───
    @Published var fps: Double = 60

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
        metalView.depthStencilPixelFormat = .none
        metalView.sampleCount = 1
        metalView.isPaused = false

        createPipeline(metalView: metalView)
        createBuffers()
    }

    // ─── Pipeline ───
    private func createPipeline(metalView: MTKView) {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "vertexMain"),
              let fragmentFn = library.makeFunction(name: "metaballFragment") else {
            fatalError("Failed to load Metal functions")
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

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Pipeline state error: \(error)")
        }
    }

    private func createBuffers() {
        // Uniforms buffer
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)
        // Balls buffer (fixed max size)
        ballsBuffer = device.makeBuffer(length: MemoryLayout<Metaball>.stride * maxBalls, options: .storageModeShared)
    }

    // ─── Public API ───
    func updateBalls(_ newBalls: [MetaballData]) {
        balls = Array(newBalls.prefix(maxBalls))
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
        fps = 1.0 / dt

        updateUniforms(time: Float(now))
        updateBallsBuffer()

        let cmdBuffer = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(ballsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    // ─── Buffer updates ───
    private func updateUniforms(time: Float) {
        var u = Uniforms(
            count: UInt32(balls.count),
            time: time,
            resolution: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            pixelRatio: pixelRatio,
            threshold: 0.378,
            _pad: (0, 0, 0)
        )
        memcpy(uniformsBuffer.contents(), &u, MemoryLayout<Uniforms>.stride)
    }

    private func updateBallsBuffer() {
        let ptr = ballsBuffer.contents().bindMemory(to: Metaball.self, capacity: maxBalls)
        for (i, ball) in balls.enumerated() {
            // Convert radius from points to normalized (divide by min dimension)
            let normRadius = ball.radius / Float(min(viewportSize.width, viewportSize.height))
            ptr[i] = Metaball(
                pos: ball.pos,
                vel: ball.vel,
                radius: normRadius,
                stretch: ball.stretch,
                phase: ball.phase,
                _pad: (0, 0, 0)
            )
        }
    }
}

// ──────────────────────────────────────────────
// Uniform structs (must match Metal)
// ──────────────────────────────────────────────

struct Uniforms {
    var count: UInt32
    var time: Float
    var resolution: SIMD2<Float>
    var pixelRatio: Float
    var threshold: Float
    var _pad: (Float, Float, Float)
}

struct Metaball {
    var pos: SIMD2<Float>
    var vel: SIMD2<Float>
    var radius: Float
    var stretch: Float
    var phase: Float
    var _pad: (Float, Float, Float)
}