# FastDrop iOS Beta (Native)

> **iOS-native rewrite** of the Flutter FastDrop app, built for iPhone 15 Pro with Metal-accelerated metaballs, SwiftUI gestures, and Network.framework P2P.

---

## 🎯 Concept

This beta implements the **HTML prototype concept** (metaball drops, drag-to-send gesture, black hole transfer scene) as a native iOS 17+ app using:

| Layer | Technology |
|-------|------------|
| **Graphics** | Metal (compute/fragment shaders) — 120 fps metaball rendering |
| **UI** | SwiftUI + custom Glassmorphism kit (matches Flutter `liquid_glass.dart`) |
| **Gestures** | SwiftUI `DragGesture` + spring physics (k=170, c=16) + Core Haptics |
| **Network** | Network.framework (`NWConnection`, `NWBrowser`, Bonjour) |
| **Architecture** | MVVM + Combine, protocol-compatible with Flutter version |

---

## 📁 Project Structure

```
ios-beta/
├── Package.swift                    # Swift Package Manager
├── README.md
├── FastDrop/
│   ├── App/
│   │   ├── FastDropApp.swift        # @main entry point
│   │   └── AppState.swift           # Global state (theme, onboarding)
│   ├── Metal/
│   │   ├── MetaballShader.metal     # Fragment shader for metaballs
│   │   ├── MetaballRenderer.swift   # MTKView delegate, uniform buffers
│   │   └── TransferSceneRenderer.swift # Rings, black hole, ripple
│   ├── Network/
│   │   ├── Protocol.swift           # Wire protocol (compatible with Flutter)
│   │   ├── DiscoveryService.swift   # Bonjour browser
│   │   └── TransferService.swift    # Sender/receiver (TCP, 1MB chunks)
│   ├── UI/
│   │   ├── HomeView.swift           # Main screen (drops + send button)
│   │   ├── TransferSceneView.swift  # Black hole transfer animation
│   │   ├── Glass/
│   │   │   └── GlassPalette.swift   # Glassmorphism kit (cards, buttons, chips)
│   │   └── Components/
│   │       ├── FileDrop.swift       # Drop model + sample data
│   │       ├── PeerChip.swift       # Peer selection chip
│   │       └── SendButton.swift     # Drag-to-send with spring physics
│   └── Resources/
│       └── Info.plist               # iOS 17+, Metal, Bonjour, Local Network
└── FastDropTests/
    └── (unit tests)
```

---

## 🚀 Getting Started

### Requirements
- Xcode 15.2+
- iOS 17.0+ (iPhone 12 or later for Metal performance)
- Apple Developer account (for device testing / TestFlight)

### Open in Xcode
```bash
cd ios-beta
xed .
```
Or open `Package.swift` directly in Xcode 15+ (SPM support).

### Build & Run
1. Select **FastDropApp** scheme
2. Choose **iPhone 15 Pro** simulator or device
3. `⌘R` to build and run

---

## 🎨 Features Implemented

| Feature | Status | Notes |
|---------|--------|-------|
| **Metaball rendering (Metal)** | ✅ | 120 fps, stretch-by-velocity, merge |
| **Drag-to-send gesture** | ✅ | Spring physics, haptic thresholds, auto-trigger |
| **Transfer scene (black hole)** | ✅ | Scatter → ring → pull → gone animation |
| **Glassmorphism UI kit** | ✅ | Cards, buttons, chips, progress, text fields |
| **Bonjour discovery** | ✅ | `_fastdrop._tcp` service type |
| **TCP transfer (1MB chunks)** | ✅ | Protocol compatible with Flutter version |
| **Theme (light/dark)** | ✅ | System + manual toggle, persisted |
| **Onboarding** | ✅ | 3 pages, auto-show on first launch |

---

## 🔧 Protocol Compatibility

Wire protocol matches Flutter `main.dart`:
- **Ports**: TCP 14680 (transfer), UDP 14681 (discovery — now Bonjour)
- **Chunk size**: 1 MB
- **Magic bytes**: `FDRP` (0x46445250)
- **Message types**: Handshake, FileHeader, Chunk, ChunkAck, Done, Cancel

---

## 📱 Target Device: iPhone 15 Pro

| Metric | Target |
|--------|--------|
| **Metaball FPS** | 120 fps (ProMotion) |
| **Gesture latency** | < 8 ms |
| **Transfer throughput** | > 100 MB/s (local Wi-Fi) |
| **Memory (idle)** | < 50 MB |
| **Memory (transfer)** | < 150 MB |

---

## 🧪 Testing

```bash
# Unit tests
swift test

# UI tests (requires device)
xcodebuild test -scheme FastDropApp -destination 'platform=iOS,name=iPhone 15 Pro'
```

---

## 📦 Build for TestFlight

1. **Archive**: `Product → Archive`
2. **Distribute**: TestFlight / App Store Connect
3. **Bundle ID**: `com.kiabi.fastdrop.beta` (separate from stable)

---

## 🔄 Relation to Stable (Flutter)

| Aspect | Stable (Flutter) | Beta (iOS Native) |
|--------|------------------|-------------------|
| **Platforms** | Android, iOS, Linux, Windows, Web | iOS 17+ only |
| **UI Framework** | Flutter (custom `liquid_glass.dart`) | SwiftUI + Metal |
| **Metaballs** | CPU canvas (downsampled) | GPU Metal shader |
| **Gestures** | `GestureDetector` + custom spring | SwiftUI `DragGesture` + `UISpringTimingParameters` |
| **Network** | `dart:io` TCP/UDP | Network.framework (`NWConnection`, Bonjour) |
| **Distribution** | Play Store, App Store, GitHub Releases | TestFlight (beta), App Store (later) |

---

## 📝 License

Same as parent project (see root `LICENSE`).

---

## 🙏 Credits

- **Concept & Design**: HTML prototype (metaballs, drag-to-send, black hole)
- **Flutter Implementation**: `kiabi-design/fast-drop` (stable cross-platform version)
- **iOS Native Rewrite**: This beta branch