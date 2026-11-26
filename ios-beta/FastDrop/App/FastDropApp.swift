import SwiftUI

// ──────────────────────────────────────────────
// FastDrop App Entry Point
// ──────────────────────────────────────────────

@main
struct FastDropApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.colorScheme)
                .onAppear {
                    // Keep screen on during transfers
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }
    }
}

// ──────────────────────────────────────────────
// Content View (Root)
// ──────────────────────────────────────────────

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOnboarding = false

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding || !showOnboarding {
                HomeView()
            } else {
                OnboardingView(onComplete: { appState.completeOnboarding() })
            }
        }
        .onAppear {
            showOnboarding = !appState.hasCompletedOnboarding
        }
    }
}

// ──────────────────────────────────────────────
// Onboarding View
// ──────────────────────────────────────────────

struct OnboardingView: View {
    let onComplete: () -> Void
    @Environment(\.colorScheme) var scheme
    @State private var page = 0

    private let pages = [
        OnboardingPage(
            title: "FastDrop",
            subtitle: "Мгновенная передача файлов между устройствами",
            icon: "arrow.up.circle.fill",
            description: "Никаких кабелей, облаков или регистраций. Просто тянешь файл к центру — и он улетает."
        ),
        OnboardingPage(
            title: "Метаболлы",
            subtitle: "Капли с физикой",
            icon: "drop.fill",
            description: "Файлы живут как жидкие капли: тянутся за пальцем, сливаются, реагируют на скорость. 60 fps на Metal."
        ),
        OnboardingPage(
            title: "Приватность",
            subtitle: "Только локальная сеть",
            icon: "lock.shield.fill",
            description: "Никаких серверов. Передача идёт напрямую через Wi-Fi / Bluetooth (P2P). Твои файлы — только твои."
        )
    ]

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Pages
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        OnboardingPageView(page: pages[i])
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: page)

                // Bottom controls
                VStack(spacing: 16) {
                    // Page indicator
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { i in
                            Circle()
                                .fill(i == page ? Color(hex: "30D158") : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
                        }
                    }

                    // Continue / Get Started button
                    Button(action: {
                        if page < pages.count - 1 {
                            withAnimation { page += 1 }
                        } else {
                            onComplete()
                        }
                    }) {
                        Text(page < pages.count - 1 ? "Далее" : "Начать")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "30D158"), Color(hex: "14A03C")],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                            )
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var backgroundGradient: some View {
        ZStack {
            Color(scheme == .dark ? Color(hex: "07120C") : Color(hex: "E9F1EC"))
            RadialGradient(
                colors: [Color(hex: "30D158").opacity(0.3), .clear],
                center: .topLeading, startRadius: 0, endRadius: 500
            )
            RadialGradient(
                colors: [Color(hex: "14BECC").opacity(0.2), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 500
            )
        }
    }
}

struct OnboardingPage {
    let title: String
    let subtitle: String
    let icon: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "30D158"), Color(hex: "14BECC")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(scheme == .dark ? .white : Color(hex: "0B0B12"))
                Text(page.subtitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(hex: "30D158"))
            }

            Text(page.description)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(scheme == .dark ? .white.opacity(0.7) : Color(hex: "3C3C43").opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// ──────────────────────────────────────────────
// Preview
// ──────────────────────────────────────────────

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}