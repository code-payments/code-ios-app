//
//  CollectionFundingStore.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// What a collection payment remembers across launches, per user: the swap id each funding leg
/// started, so a retry finds that swap instead of starting a second one, the top-up a payment
/// ordered, so a retry waits on it instead of ordering again, and the currency the user last paid
/// a collection in, which the next collection's picker opens on.
@MainActor
final class CollectionFundingStore {

    /// A top-up ordered for a payment whose Dollars haven't been seen yet.
    struct PendingTopUp: Codable, Equatable {
        /// The order's `partnerOrderRef`, for tracing it with Coinbase.
        let orderRef: String
        /// What the order adds, in USD.
        let amountUSD: Decimal
        /// The Dollars balance, in USD, read before the order was placed.
        let baselineUSD: Decimal
        /// When the record was written, just before the order was placed.
        let placedAt: Date
        /// Whether Apple Pay reported the payment authorized. One that never was charged nothing,
        /// unless the app died between the user authorizing it and the report arriving.
        var authorized: Bool
    }

    private let defaults: UserDefaults
    private let swapsKey: String
    private let lastPaidKey: String
    private let topUpsKey: String

    init(userID: UserID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.swapsKey = "collectionFunding.swapIDs.\(userID.uuidString)"
        self.lastPaidKey = "collectionFunding.lastPaidCurrency.\(userID.uuidString)"
        self.topUpsKey = "collectionFunding.pendingTopUps.\(userID.uuidString)"
    }

    // MARK: - Swap ids -

    /// The swap id the leg converting out of `source` started for `requestID`, if one is pending.
    func swapID(for requestID: PaymentRequestID, source: String) -> SwapId? {
        swaps[Self.key(requestID, source)].flatMap(SwapId.init(data:))
    }

    /// Records `swapID` before its swap is submitted, so an attempt that dies mid-swap leaves it behind.
    func setSwapID(_ swapID: SwapId, for requestID: PaymentRequestID, source: String) {
        var swaps = swaps
        swaps[Self.key(requestID, source)] = swapID.value
        self.swaps = swaps
    }

    /// Forgets a leg's swap once it is terminal, so a later leg from the same source gets its own id.
    func removeSwapID(for requestID: PaymentRequestID, source: String) {
        var swaps = swaps
        swaps[Self.key(requestID, source)] = nil
        self.swaps = swaps
    }

    /// Forgets every leg of `requestID`, once its payment has landed.
    func clearSwapIDs(for requestID: PaymentRequestID) {
        let prefix = Self.prefix(requestID)
        self.swaps = swaps.filter { !$0.key.hasPrefix(prefix) }
    }

    // MARK: - Pending top-up -

    /// The top-up `requestID`'s payment ordered and hasn't seen land, if any.
    func pendingTopUp(for requestID: PaymentRequestID) -> PendingTopUp? {
        topUps[requestID.data.hexEncodedString()]
            .flatMap { try? JSONDecoder().decode(PendingTopUp.self, from: $0) }
    }

    /// Records `topUp` before its order is placed, so an attempt that dies mid-order leaves it behind.
    func setPendingTopUp(_ topUp: PendingTopUp, for requestID: PaymentRequestID) {
        var topUps = topUps
        topUps[requestID.data.hexEncodedString()] = try? JSONEncoder().encode(topUp)
        self.topUps = topUps
    }

    /// Marks the pending top-up authorized, once Apple Pay says so.
    func markTopUpAuthorized(for requestID: PaymentRequestID) {
        guard var topUp = pendingTopUp(for: requestID) else { return }
        topUp.authorized = true
        setPendingTopUp(topUp, for: requestID)
    }

    /// Forgets the pending top-up once its Dollars are seen or its order is known to have failed.
    func clearPendingTopUp(for requestID: PaymentRequestID) {
        var topUps = topUps
        topUps[requestID.data.hexEncodedString()] = nil
        self.topUps = topUps
    }

    // MARK: - Last paid currency -

    /// The mint (base58) of the last successful collection payment, or nil before the first one.
    var lastPaidCurrency: String? {
        defaults.string(forKey: lastPaidKey)
    }

    /// Called only once a collection payment succeeds; a failed or abandoned one leaves the last value.
    func recordPaid(currency: String) {
        defaults.set(currency, forKey: lastPaidKey)
    }

    // MARK: - Storage -

    private var swaps: [String: Data] {
        get { defaults.dictionary(forKey: swapsKey) as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: swapsKey) }
    }

    private var topUps: [String: Data] {
        get { defaults.dictionary(forKey: topUpsKey) as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: topUpsKey) }
    }

    private static func prefix(_ requestID: PaymentRequestID) -> String {
        "\(requestID.data.hexEncodedString())|"
    }

    private static func key(_ requestID: PaymentRequestID, _ source: String) -> String {
        prefix(requestID) + source
    }
}
