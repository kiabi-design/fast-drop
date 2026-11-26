@preconcurrency import MetalKit
import SwiftUI
import Combine

// ──────────────────────────────────────────────
// Metaball data (matches Metal struct)
// ──────────────────────────────────────────────

public struct MetaballData {
    public var pos: SIMD2<Float>      // normalized 0..1
    public var vel: SIMD2<Float>      // normalized velocity
    public var radius: Float          // base radius in points
    public var stretch: Float         // 0..0.55
    public var phase: Float           // idle wobble

    public init(pos: SIMD2<Float>, vel: SIMD2<Float>, radius: Float, stretch: Float, phase: Float) {
        self.pos = pos
        self.vel = vel
        self.radius = radius
        self.stretch = stretch
        self.phase = phase
    }
}

// MetaballRenderer is non-isolated because MTKViewDelegate methods run on the render thread
// @Published properties are @MainActor isolated via property wrapper
public final class MetaballRenderer: NSObject, MTKViewDelegate {
    // ─── Metal resources (nonisolated - accessed from render thread) ───
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    nonisolated(unsafe) private var pipelineState: MTLRenderPipelineState!
    nonisolated(unsafe) private var uniformsBuffer: MTLBuffer!
    nonisolated(unsafe) private var ballsBuffer: MTLBuffer!

    // ─── State (nonisolated - accessed from render thread) ───
    nonisolated(unsafe) private var balls: [MetaballData] = []
    nonisolated(unsafe) private var viewportSize: CGSize = .zero
    nonisolated(unsafe) private var pixelRatio: Float = 1.0
    nonisolated(unsafe) private var lastTime: CFTimeInterval = 0
    private let maxBalls = 32

    // ─── Published for SwiftUI (@MainActor isolated) ───
    @MainActor @Published var fps: Double = 60

    // Private init - use create() factory method
    private init(device: MTLDevice, queue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = queue
        super.init()
        createPipeline()
        createBuffers()
    }

    // Factory method to create and configure on @MainActor
    @MainActor
    static func create(metalView: MTKView) -> MetaballRenderer? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        let renderer = MetaballRenderer(device: device, queue: queue)

        metalView.device = device
        metalView.delegate = renderer
        metalView.preferredFramesPerSecond = 120
        metalView.framebufferOnly = true
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .invalid
        metalView.sampleCount = 1
        metalView.isPaused = false

        return renderer
    }

    // ─── Pipeline ───
    private func createPipeline() {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "vertexMain"),
              let fragmentFn = library.makeFunction(name: "metaballFragment") else {
            fatalError("Failed to load Metal functions")
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

    // ─── Public API (@MainActor for SwiftUI) ───
    @MainActor
    func updateBalls(_ newBalls: [MetaballData]) {
        balls = Array(newBalls.prefix(maxBalls))
    }

    @MainActor
    func updateViewport(_ size: CGSize, scale: CGFloat) {
        viewportSize = size
        pixelRatio = Float(scale)
    }

    // ─── MTKViewDelegate (@MainActor - runs on main thread in Swift 6) ───
    @MainActor
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        pixelRatio = Float(view.contentScaleFactor)
    }

    @MainActor
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

public struct Uniforms {
    public var count: UInt32
    public var time: Float
    public var resolution: SIMD2<Float>
    public var pixelRatio: Float
    public var threshold: Float
    public var _pad: (Float, Float, Float)

    public init(count: UInt32, time: Float, resolution: SIMD2<Float>, pixelRatio: Float, threshold: Float) {
        self.count = count
        self.time = time
        self.resolution = resolution
        self.pixelRatio = pixelRatio
        self.threshold = threshold
        self._pad = (0, 0, 0)
    }
}

public struct Metaball {
    public var pos: SIMD2<Float>
    public var vel: SIMD2<Float>
    public var radius: Float
    public var stretch: Float
    public var phase: Float
    public var _pad: (Float, Float, Float)

    public init(pos: SIMD2<Float>, vel: SIMD2<Float>, radius: Float, stretch: Float, phase: Float) {
        self.pos = pos
        self.vel = vel
        self.radius = radius
        self.stretch = stretch
        self.phase = phase
        self._pad = (0, 0, 0)
    }
}