import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @State private var showPaywall = false

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(symbol: "figure.stand",
             title: String(localized: "Your earbuds can see your posture"),
             body: String(localized: "Headphones that support head tracking know when your head drops toward a screen. Neckline turns that into a gentle reminder to sit tall.")),
        Page(symbol: "waveform",
             title: String(localized: "Nudges you can hear"),
             body: String(localized: "Start a session and get on with your work. When your head stays down too long, a quiet voice in your earbuds says \"chin up\".")),
        Page(symbol: "figure.mind.and.body",
             title: String(localized: "Two-minute neck resets"),
             body: String(localized: "Guided stretches where every rep is checked against your real head movement. No earbuds? They run in guided mode with on-screen timing.")),
        Page(symbol: "cross.case",
             title: String(localized: "Move gently"),
             body: String(localized: "Neckline is a wellness tool, not a medical device. Never stretch into pain, and talk to a clinician about persistent neck pain.")),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    // Scrolls only when the page doesn't fit (large Dynamic
                    // Type, small iPhones); otherwise it stays centred.
                    GeometryReader { geo in
                        ScrollView {
                            pageContent(pages[i])
                                .padding(.horizontal, 28)
                                .padding(.vertical, 24)
                                // Keep text clear of the page dots.
                                .padding(.bottom, 32)
                                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    showPaywall = true
                }
            } label: {
                Text(page < pages.count - 1 ? String(localized: "Continue") : String(localized: "Get started"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentFill)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showPaywall, onDismiss: onFinish) {
            PaywallView()
        }
    }

    private func pageContent(_ page: Page) -> some View {
        VStack(spacing: 22) {
            Image(systemName: page.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 128, height: 128)
                .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 32))
            Text(page.title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
