import SwiftUI

/// A deliberately short in-app splash keeps the first app frame branded while the system
/// launch screen hands over. The menu is created only after it clears, so its BGM begins
/// with the actual menu rather than underneath the logo.
struct AppLaunchView: View {
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            if !isShowingSplash {
                ContentView()
                    .transition(.opacity)
            }

            if isShowingSplash {
                SplashMarkView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                isShowingSplash = false
            }
        }
    }
}

private struct SplashMarkView: View {
    private let screenDark = Color(red: 0.027, green: 0.094, blue: 0.129)

    var body: some View {
        GeometryReader { geo in
            let logoScale = min(1.35, max(0.8, geo.size.width / 320))

            ZStack {
                Image("AppLogo")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.28)
                    .blur(radius: 38)
                    .overlay(screenDark.opacity(0.58))
                    .clipped()

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104 * logoScale, height: 104 * logoScale)
                    .clipShape(RoundedRectangle(cornerRadius: 23 * logoScale, style: .continuous))
                .accessibilityLabel("MazDu")
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}
