import Foundation
import Observation
import StoreKit

/// The one-time "Full Fight Card" unlock. Sandbag and Vitrine Bloom are free;
/// The Warden and every opponent added later need the unlock.
@MainActor
@Observable
final class UnlockStore {
    static let shared = UnlockStore()

    static let productID = "com.airdodge.AirpodsGame.fullcard"
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://dautovri.com/airboxer-privacy")!

    enum State: Equatable {
        case idle, purchasing, pending
        case failed(String)
    }

    private(set) var isUnlocked = false
    private(set) var product: Product?
    /// The App Store answered with no product (offline, or not set up).
    private(set) var productUnavailable = false
    var state: State = .idle

    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {
        // From launch: refunds and purchases approved later (Ask to Buy, SCA)
        // arrive here and must be finished.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
        Task { await load() }
    }

    func isLocked(_ opponent: OpponentDefinition) -> Bool {
        opponent.requiresUnlock && !isUnlocked
    }

    func load() async {
        await refreshEntitlement()
        let products = (try? await Product.products(for: [Self.productID])) ?? []
        product = products.first
        productUnavailable = products.isEmpty
    }

    func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ABUnlocked") { owned = true }
        #endif
        isUnlocked = owned
    }

    func purchase() async {
        guard let product else { return }
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlement()
                state = .idle
            case .success(.unverified):
                state = .failed("The purchase couldn't be verified.")
            case .pending:
                state = .pending
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }
}
