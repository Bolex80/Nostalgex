import XCTest
@testable import Nostalgex

final class TipJarTests: XCTestCase {

    // MARK: - Purchase result mapping

    func testVerifiedThanksAndFinishes() {
        let r = TipJarLogic.resolve(.verified(transactionID: 42), alreadyThanked: [])
        XCTAssertEqual(r, TipResolution(outcome: .thanks, transactionToFinish: 42))
    }

    func testVerifiedAlreadyThankedStillFinishesButShowsNothing() {
        let r = TipJarLogic.resolve(.verified(transactionID: 42), alreadyThanked: [42])
        XCTAssertEqual(r, TipResolution(outcome: .none, transactionToFinish: 42))
    }

    func testUnverifiedIsQuietFailureAndStillFinishes() {
        let r = TipJarLogic.resolve(.unverified(transactionID: 7), alreadyThanked: [])
        XCTAssertEqual(r, TipResolution(outcome: .failed, transactionToFinish: 7))
        XCTAssertEqual(TipJarLogic.statusLine(for: r.outcome), TipJarLogic.failedLine)
    }

    func testUserCancelledDoesNothing() {
        let r = TipJarLogic.resolve(.userCancelled, alreadyThanked: [])
        XCTAssertEqual(r, TipResolution(outcome: .none, transactionToFinish: nil))
        XCTAssertNil(TipJarLogic.statusLine(for: r.outcome))
    }

    func testPendingShowsWaitingForApproval() {
        let r = TipJarLogic.resolve(.pending, alreadyThanked: [])
        XCTAssertEqual(r, TipResolution(outcome: .pending, transactionToFinish: nil))
        XCTAssertEqual(TipJarLogic.statusLine(for: r.outcome), "Waiting for approval")
    }

    func testThrownErrorIsQuietFailure() {
        let r = TipJarLogic.resolve(.failed, alreadyThanked: [])
        XCTAssertEqual(r, TipResolution(outcome: .failed, transactionToFinish: nil))
        XCTAssertEqual(TipJarLogic.statusLine(for: r.outcome), TipJarLogic.failedLine)
    }

    func testThanksHasNoStatusLine() {
        XCTAssertNil(TipJarLogic.statusLine(for: .thanks))
    }

    func testUserFacingLinesHaveNoEmDashOrEmoji() {
        for line in [TipJarLogic.pendingLine, TipJarLogic.failedLine] + TipProduct.allCases.map(\.rowTitle) {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            XCTAssertTrue(line.unicodeScalars.allSatisfy { $0.isASCII || $0 == "\u{2019}" }, line)
        }
    }

    // MARK: - Products

    func testProductIDsAndFocusIDs() {
        XCTAssertEqual(TipProduct.allIDs, [
            "com.muellhaus.nostalgex.tip.small",
            "com.muellhaus.nostalgex.tip.big",
            "com.muellhaus.nostalgex.tip.pizza"
        ])
        XCTAssertEqual(TipProduct.allCases.map(\.focusID), ["tip_small", "tip_big", "tip_pizza"])
        XCTAssertEqual(TipProduct.allCases.map(\.rowTitle), ["SMALL COFFEE", "BIG COFFEE", "PIZZA NIGHT"])
    }

    private struct FakeProduct: Equatable {
        let id: String
        let price: Decimal
    }

    func testSortsByPriceAscending() {
        let input = [
            FakeProduct(id: TipProduct.pizza.rawValue, price: Decimal(string: "9.99")!),
            FakeProduct(id: TipProduct.small.rawValue, price: Decimal(string: "1.99")!),
            FakeProduct(id: TipProduct.big.rawValue, price: Decimal(string: "4.99")!)
        ]
        let sorted = TipJarLogic.sortedByPrice(input, id: \.id, price: \.price)
        XCTAssertEqual(sorted.map(\.id), TipProduct.allIDs)
    }

    func testPriceTiesKeepFixedOrder() {
        let input = [
            FakeProduct(id: TipProduct.pizza.rawValue, price: 5),
            FakeProduct(id: TipProduct.big.rawValue, price: 5),
            FakeProduct(id: TipProduct.small.rawValue, price: 5)
        ]
        let sorted = TipJarLogic.sortedByPrice(input, id: \.id, price: \.price)
        XCTAssertEqual(sorted.map(\.id), TipProduct.allIDs)
    }

    // MARK: - Thank once per transaction id

    func testLedgerThanksOncePerTransactionID() {
        var ledger = TipThankLedger()
        XCTAssertTrue(ledger.recordThanks(for: 100))
        XCTAssertFalse(ledger.recordThanks(for: 100))
        XCTAssertTrue(ledger.recordThanks(for: 101))

        // The same transaction arriving again (purchase result, then Transaction.updates)
        // maps to no thank-you.
        let again = TipJarLogic.resolve(.verified(transactionID: 100), alreadyThanked: ledger.asSet)
        XCTAssertEqual(again.outcome, .none)
        XCTAssertEqual(again.transactionToFinish, 100)
    }

    func testLedgerSurvivesRelaunch() {
        let suite = "TipJarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var ledger = TipThankLedger.load(from: defaults)
        ledger.recordThanks(for: 9_000_000_000_000_000_001)
        ledger.save(to: defaults)

        let reloaded = TipThankLedger.load(from: defaults)
        XCTAssertTrue(reloaded.contains(9_000_000_000_000_000_001))
        XCTAssertFalse(TipThankLedger.load(from: defaults).asSet.isEmpty)
    }

    func testLedgerIsCapped() {
        var ledger = TipThankLedger()
        for id in 0..<UInt64(TipThankLedger.cap + 25) { ledger.recordThanks(for: id) }
        XCTAssertEqual(ledger.ids.count, TipThankLedger.cap)
        XCTAssertFalse(ledger.contains(0))
        XCTAssertTrue(ledger.contains(UInt64(TipThankLedger.cap + 24)))
    }
}
