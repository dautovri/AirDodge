import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: ProStore.productIDs) {
            VStack(spacing: 16) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 24))
                Text("Neckline Pro")
                    .font(.largeTitle.weight(.bold))
                VStack(alignment: .leading, spacing: 10) {
                    perk("infinity", String(localized: "Unlimited posture sessions"))
                    perk("list.bullet.rectangle", String(localized: "Every routine, including Tech-Neck Relief"))
                    perk("chart.bar.xaxis", String(localized: "Upright-time and posture-score trends"))
                    perk("lock.shield", String(localized: "Private: head motion never leaves your iPhone"))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .subscriptionStorePolicyDestination(url: ProStore.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: ProStore.privacyURL, for: .privacyPolicy)
        .tint(Theme.accentFill)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(let verification)) = result {
                await ProStore.shared.handlePurchase(verification)
                dismiss()
            } else {
                await ProStore.shared.refresh()
            }
        }
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
        }
        .font(.body)
    }
}
