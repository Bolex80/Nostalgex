import Foundation
import Observation
import StoreKit

// MARK: - Tip jar
//
// Three consumable tips under SUPPORT NOSTALGEX. A tip unlocks nothing. The only thing
// kept on disk is the list of transaction ids already thanked, so an Ask to Buy approval
// that also arrives through Transaction.updates never shows the thank-you card twice.
// No analytics: tips stay off the privacy label.

/// The three tip products, in the order they should appear when prices tie.
enum TipProduct: String, CaseIterable {
    case small = "com.muellhaus.nostalgex.tip.small"
    case big = "com.muellhaus.nostalgex.tip.big"
    case pizza = "com.muellhaus.nostalgex.tip.pizza"

    static var allIDs: [String] { allCases.map(\.rawValue) }

    /// Row title in Settings. Product names come from StoreKit, but the row titles match
    /// the rest of the Settings page (upper case, fixed).
    var rowTitle: String {
        switch self {
        case .small: return "SMALL COFFEE"
        case .big: return "BIG COFFEE"
        case .pizza: return "PIZZA NIGHT"
        }
    }

    /// Focus and scroll id for the Settings row.
    var focusID: String {
        switch self {
        case .small: return "tip_small"
        case .big: return "tip_big"
        case .pizza: return "tip_pizza"
        }
    }
}

/// What StoreKit reported, reduced to something a test can build.
enum TipPurchaseEvent: Equatable {
    case verified(transactionID: UInt64)
    case unverified(transactionID: UInt64)
    case userCancelled
    case pending
    case failed
}

/// What the app shows for a purchase result.
enum TipOutcome: Equatable {
    /// Nothing at all (cancelled, or a transaction already thanked).
    case none
    /// The full-screen thank-you card.
    case thanks
    /// The quiet "Waiting for approval" line.
    case pending
    /// The quiet failure line.
    case failed
}

struct TipResolution: Equatable {
    let outcome: TipOutcome
    /// The transaction to finish, if there is one. Every transaction is finished, verified
    /// or not: there is nothing to unlock, so holding one open only makes StoreKit
    /// redeliver it.
    let transactionToFinish: UInt64?
}

enum TipJarLogic {
    static let pendingLine = "Waiting for approval"
    static let failedLine = "That tip didn't go through."

    /// Pure mapping from a purchase result to what the app does.
    static func resolve(_ event: TipPurchaseEvent, alreadyThanked: Set<UInt64>) -> TipResolution {
        switch event {
        case .verified(let id):
            return TipResolution(
                outcome: alreadyThanked.contains(id) ? .none : .thanks,
                transactionToFinish: id
            )
        case .unverified(let id):
            return TipResolution(outcome: .failed, transactionToFinish: id)
        case .userCancelled:
            return TipResolution(outcome: .none, transactionToFinish: nil)
        case .pending:
            return TipResolution(outcome: .pending, transactionToFinish: nil)
        case .failed:
            return TipResolution(outcome: .failed, transactionToFinish: nil)
        }
    }

    /// The quiet line under the tip rows for an outcome, or nil to clear it.
    static func statusLine(for outcome: TipOutcome) -> String? {
        switch outcome {
        case .pending: return pendingLine
        case .failed: return failedLine
        case .none, .thanks: return nil
        }
    }

    /// Cheapest first. Ties keep the fixed small, big, pizza order so the rows never shuffle.
    static func sortedByPrice<T>(_ items: [T], id: (T) -> String, price: (T) -> Decimal) -> [T] {
        let order = Dictionary(uniqueKeysWithValues: TipProduct.allIDs.enumerated().map { ($1, $0) })
        return items.sorted { a, b in
            let pa = price(a), pb = price(b)
            if pa != pb { return pa < pb }
            return (order[id(a)] ?? Int.max) < (order[id(b)] ?? Int.max)
        }
    }
}

/// Transaction ids already thanked. Capped so it never grows without bound.
struct TipThankLedger {
    static let defaultsKey = "tipJar.thankedTransactionIDs"
    static let cap = 200

    private(set) var ids: [UInt64]

    init(ids: [UInt64] = []) {
        self.ids = ids
    }

    var asSet: Set<UInt64> { Set(ids) }

    func contains(_ id: UInt64) -> Bool { ids.contains(id) }

    /// Records a thank-you. Returns false when this id was already thanked, in which case
    /// the caller must not show the card again.
    @discardableResult
    mutating func recordThanks(for id: UInt64) -> Bool {
        guard !ids.contains(id) else { return false }
        ids.append(id)
        if ids.count > Self.cap { ids.removeFirst(ids.count - Self.cap) }
        return true
    }

    static func load(from defaults: UserDefaults = .standard) -> TipThankLedger {
        let stored = defaults.array(forKey: defaultsKey) as? [String] ?? []
        return TipThankLedger(ids: stored.compactMap(UInt64.init))
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(ids.map(String.init), forKey: Self.defaultsKey)
    }
}

// MARK: - Store

@Observable
@MainActor
final class TipJar {
    static let shared = TipJar()

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        /// No network, products not live yet, or StoreKit refused. The rows stay hidden.
        case unavailable
    }

    private(set) var loadState: LoadState = .idle
    private(set) var products: [Product] = []
    private(set) var isPurchasing = false
    /// The quiet pending or failure line under the tip rows.
    private(set) var statusLine: String?
    /// Drives the full-screen thank-you card.
    var showThanks = false

    @ObservationIgnored private var ledger: TipThankLedger
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ledger = TipThankLedger.load(from: defaults)
    }

    /// Rows show only once every product loaded.
    var tipsAvailable: Bool { loadState == .loaded && !products.isEmpty }

    /// Apple requires a Transaction.updates listener from launch: an Ask to Buy approval
    /// or an interrupted purchase can complete while the app is closed or elsewhere.
    func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update, fromPurchase: false)
            }
        }
    }

    func loadProductsIfNeeded() async {
        guard loadState == .idle || loadState == .unavailable else { return }
        loadState = .loading
        do {
            let loaded = try await Product.products(for: TipProduct.allIDs)
            guard !loaded.isEmpty else {
                loadState = .unavailable
                return
            }
            products = TipJarLogic.sortedByPrice(loaded, id: \.id, price: \.price)
            loadState = .loaded
        } catch {
            print("[Nostalgex] Tip products unavailable: \(error.localizedDescription)")
            loadState = .unavailable
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        statusLine = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification, fromPurchase: true)
            case .userCancelled:
                apply(TipJarLogic.resolve(.userCancelled, alreadyThanked: ledger.asSet))
            case .pending:
                apply(TipJarLogic.resolve(.pending, alreadyThanked: ledger.asSet))
            @unknown default:
                apply(TipJarLogic.resolve(.failed, alreadyThanked: ledger.asSet))
            }
        } catch {
            print("[Nostalgex] Tip purchase failed: \(error.localizedDescription)")
            apply(TipJarLogic.resolve(.failed, alreadyThanked: ledger.asSet))
        }
    }

    func dismissThanks() {
        showThanks = false
    }

    // MARK: Private

    private func handle(_ verification: VerificationResult<Transaction>, fromPurchase: Bool) async {
        let event: TipPurchaseEvent
        let transaction: Transaction
        switch verification {
        case .verified(let t):
            event = .verified(transactionID: t.id)
            transaction = t
        case .unverified(let t, _):
            event = .unverified(transactionID: t.id)
            transaction = t
        }

        // Only tips belong to this listener. Anything else is left alone.
        guard TipProduct(rawValue: transaction.productID) != nil else { return }

        var resolution = TipJarLogic.resolve(event, alreadyThanked: ledger.asSet)
        // A background update that fails verification is finished quietly; there is no
        // tap in flight to explain it to.
        if !fromPurchase, resolution.outcome == .failed {
            resolution = TipResolution(outcome: .none, transactionToFinish: resolution.transactionToFinish)
        }
        if resolution.transactionToFinish != nil {
            await transaction.finish()
        }
        apply(resolution)
    }

    private func apply(_ resolution: TipResolution) {
        if resolution.outcome == .thanks, let id = resolution.transactionToFinish {
            if ledger.recordThanks(for: id) {
                ledger.save(to: defaults)
                statusLine = nil
                showThanks = true
            }
            return
        }
        if resolution.outcome == .none { return }
        statusLine = TipJarLogic.statusLine(for: resolution.outcome)
    }
}
