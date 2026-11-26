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
        if storedScheme == "light" {
            colorScheme = .light
        } else if storedScheme == "dark" {
            colorScheme = .dark
        }
        hasCompletedOnboarding = storedOnboarding
    }

    func setColorScheme(_ scheme: ColorScheme) {
        colorScheme = scheme
        storedScheme = scheme == .light ? "light" : "dark"
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        storedOnboarding = true
    }
}