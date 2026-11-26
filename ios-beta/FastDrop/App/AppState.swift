import SwiftUI
import Combine

// ──────────────────────────────────────────────
// App State (Singleton ObservableObject)
// ──────────────────────────────────────────────

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var colorScheme: ColorScheme = .light
    @Published var isFirstLaunch = true
    @Published var hasCompletedOnboarding = false

    @AppStorage("colorScheme") private var storedScheme: String = "system"
    @AppStorage("hasCompletedOnboarding") private var storedOnboarding: Bool = false

    private init() {
        // Load saved preferences
        if let scheme = ColorScheme(rawValue: storedScheme) {
            colorScheme = scheme
        }
        hasCompletedOnboarding = storedOnboarding
    }

    func setColorScheme(_ scheme: ColorScheme) {
        colorScheme = scheme
        storedScheme = scheme.rawValue
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        storedOnboarding = true
    }
}

// ──────────────────────────────────────────────
// ColorScheme Extension
// ──────────────────────────────────────────────

extension ColorScheme {
    init?(rawValue: String) {
        switch rawValue {
        case "light": self = .light
        case "dark": self = .dark
        case "system": self = .light // fallback, actual system handled by view
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .light: return "light"
        case .dark: return "dark"
        @unknown default: return "system"
        }
    }
}