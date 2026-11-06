import SwiftUI

@main
struct PlingApp: App {
    @StateObject private var store = AppStore.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.brand)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                SplashView()
            case .onboarding:
                OnboardingView()
            case .ready:
                MainView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.phase)
        .task { await store.bootstrap() }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()
            VStack(spacing: 16) {
                LogoView(size: 96)
                ProgressView().tint(.white)
            }
        }
    }
}

struct LogoView: View {
    var size: CGFloat = 80

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(.white)
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.5, weight: .black))
                .foregroundStyle(Theme.gradient)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}
