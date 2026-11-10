import StoreKit
import StoreKitTest
import Testing
@testable import AirpodsGame

/// Subscription entitlement against the local StoreKit configuration
/// (`AirpodsGame/Neckline.storekit`). Serialized: the tests share one store.
@Suite(.serialized) struct ProStoreTests {
    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Neckline")
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// The entitlement list settles a moment after a store change, so poll.
    private func proBecomes(_ expected: Bool) async -> Bool {
        for _ in 0..<50 {
            await ProStore.shared.refresh()
            if await ProStore.shared.isPro == expected { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    @Test func bothPlansLoadAndYearlyHasAFreeTrial() async throws {
        let session = try makeSession()
        defer { withExtendedLifetime(session) {} }
        let ids = await ProStore.productIDs
        let yearlyID = await ProStore.yearlyID
        let products = try await Product.products(for: ids)
        #expect(Set(products.map(\.id)) == Set(ids))
        let yearly = try #require(products.first { $0.id == yearlyID })
        #expect(yearly.subscription?.introductoryOffer?.paymentMode == .freeTrial)
    }

    @Test(arguments: [true, false])
    func purchaseUnlocksProAndClearingRevokesIt(yearly: Bool) async throws {
        let session = try makeSession()
        let id = yearly ? await ProStore.yearlyID : await ProStore.monthlyID

        let startsLocked = await proBecomes(false)
        #expect(startsLocked)

        _ = try await session.buyProduct(identifier: id)
        let unlocked = await proBecomes(true)
        #expect(unlocked, "purchase should unlock Pro")

        session.clearTransactions()
        let revoked = await proBecomes(false)
        #expect(revoked, "clearing the purchase should revoke Pro")
    }
}
