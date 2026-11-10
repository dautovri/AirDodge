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

        await ProStore.shared.refresh()
        let before = await ProStore.shared.isPro
        #expect(!before)

        _ = try await session.buyProduct(identifier: id)
        await ProStore.shared.refresh()
        let after = await ProStore.shared.isPro
        #expect(after)

        session.clearTransactions()
        await ProStore.shared.refresh()
        let cleared = await ProStore.shared.isPro
        #expect(!cleared)
    }
}
