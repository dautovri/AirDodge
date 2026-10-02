import StoreKit
import SwiftUI

/// Paywall for the one-time Full Fight Card unlock. Always closable; the two
/// free opponents stay playable either way.
struct UnlockView: View {
    @State private var store = UnlockStore.shared
    @Environment(\.dismiss) private var dismiss

    private let features: [(String, String)] = [
        ("figure.boxing", "The Warden — the 47-1 boss with near-reflex-limit tells"),
        ("plus.circle.fill", "Every opponent added in future updates, included"),
        ("hand.thumbsup.fill", "One payment. No ads, no subscription, no tracking"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("🥊")
                            .font(.system(size: 56))
                            .accessibilityHidden(true)
                        Text("Full Fight Card")
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                            .foregroundStyle(
                                LinearGradient(colors: [.yellow, .orange],
                                               startPoint: .top, endPoint: .bottom)
                            )
                        Text("Sandbag and Vitrine Bloom are free. Unlock the rest of the roster.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(features, id: \.1) { symbol, text in
                            Label {
                                Text(text).foregroundStyle(.white)
                            } icon: {
                                Image(systemName: symbol).foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.white.opacity(0.06), in: .rect(cornerRadius: 18))

                    if store.isUnlocked {
                        Label("Full card unlocked", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Button("Back to the Ring") { dismiss() }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                    } else {
                        purchaseButton
                        stateMessage
                        legal
                    }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.06, green: 0.05, blue: 0.09).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.orange)
        .task { if store.product == nil { await store.load() } }
        .onChange(of: store.isUnlocked) { _, unlocked in if unlocked { dismiss() } }
    }

    @ViewBuilder
    private var purchaseButton: some View {
        if let product = store.product {
            Button {
                Task { await store.purchase() }
            } label: {
                Text("Unlock for \(product.displayPrice)")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(store.state == .purchasing)
        } else if store.productUnavailable {
            VStack(spacing: 8) {
                Text("The price couldn't load. Check your connection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await store.load() } }
            }
        } else {
            ProgressView("Loading price…")
        }
    }

    @ViewBuilder
    private var stateMessage: some View {
        switch store.state {
        case .pending:
            Text("Waiting for approval. The card unlocks as soon as it goes through.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.red)
        case .idle, .purchasing:
            EmptyView()
        }
    }

    private var legal: some View {
        VStack(spacing: 10) {
            Text("One-time purchase, charged to your Apple Account.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 18) {
                Button("Restore Purchases") { Task { await store.restore() } }
                Link("Terms of Use", destination: UnlockStore.termsURL)
                Link("Privacy Policy", destination: UnlockStore.privacyURL)
            }
            .font(.footnote.weight(.medium))
        }
    }
}
