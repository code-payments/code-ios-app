//
//  CollectionFundingStore.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// What a collection payment remembers across launches, per user: the swap id each funding leg
/// started, so a retry finds that swap instead of starting a second one, and the currency the
/// user last paid a collection in, which the next collection's picker opens on.
@MainActor
final class CollectionFundingStore {

    private let defaults: UserDefaults
    private let swapsKey: String
    private let lastPaidKey: String

    init(userID: UserID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.swapsKey = "collectionFunding.swapIDs.\(userID.uuidString)"
        self.lastPaidKey = "collectionFunding.lastPaidCurrency.\(userID.uuidString)"
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

    private static func prefix(_ requestID: PaymentRequestID) -> String {
        "\(requestID.data.hexEncodedString())|"
    }

    private static func key(_ requestID: PaymentRequestID, _ source: String) -> String {
        prefix(requestID) + source
    }
}
