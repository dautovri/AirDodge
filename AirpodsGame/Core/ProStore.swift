import Foundation
import Observation
import StoreKit

/// Neckline Pro: auto-renewable subscription (monthly / yearly, one group).
/// The paywall UI is StoreKit's `SubscriptionStoreView`; this type only
/// tracks the entitlement.
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let monthlyID = "com.airdodge.AirpodsGame.pro.monthly"
    static let yearlyID = "com.airdodge.AirpodsGame.pro.yearly"
    static let productIDs = [yearlyID, monthlyID]

    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://dautovri.com/airboxer-privacy")!

    private(set) var isPro = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {
        // Renewals, refunds and Ask to Buy approvals arrive here.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-NLPro") { active = true }
        #endif
        isPro = active
    }

    /// Applies a purchase made on the paywall straight away. The entitlement
    /// list can lag a moment behind a fresh purchase, so the buyer shouldn't
    /// have to wait for it.
    func handlePurchase(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification,
              Self.productIDs.contains(transaction.productID),
              transaction.revocationDate == nil else { return }
        await transaction.finish()
        isPro = true
    }

    enum RestoreOutcome: Equatable {
        case restored
        case nothingToRestore
        case failed
    }

    /// Syncs with the App Store and reports what the buyer should be told.
    /// A cancelled sign-in counts as a failure so the button never looks inert.
    func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch {
            await refresh()
            return isPro ? .restored : .failed
        }
        await refresh()
        return isPro ? .restored : .nothingToRestore
    }
}
