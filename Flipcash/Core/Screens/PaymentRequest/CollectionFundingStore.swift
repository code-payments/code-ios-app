//
//  CollectionFundingStore.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// What a collection payment remembers across launches, per user: the swap id and funding intent
/// id each funding leg started under, with the currency it converts from and into, so a retry for
/// the same pair finds that swap instead of starting a second one and never funds it under a second
/// intent, the top-up a payment
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
        /// The mint, in base58, the payment was planned to pay in when the order was placed. Nil
        /// in a record an earlier build wrote.
        var payingCurrency: String?
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

    /// The ids a funding leg's swap runs under, kept from before the swap starts until it is terminal.
    struct LegIDs: Equatable {
        let swapID: SwapId
        /// The id of the intent that funds the swap. Nil only for a leg stored before funding ids
        /// were kept.
        let fundingIntentID: PublicKey?

        /// Stored as the swap id's 32 bytes followed by the funding intent id's 32.
        fileprivate var stored: Data {
            swapID.value + (fundingIntentID?.data ?? Data())
        }

        init(swapID: SwapId, fundingIntentID: PublicKey?) {
            self.swapID = swapID
            self.fundingIntentID = fundingIntentID
        }

        /// Fresh ids for a leg about to start a swap of its own.
        static func generate() -> LegIDs {
            LegIDs(swapID: .generate(), fundingIntentID: KeyPair.generate()!.publicKey)
        }

        /// The same swap id with a funding intent id, for a leg stored without one.
        func withFundingIntentID() -> LegIDs {
            fundingIntentID == nil ? LegIDs(swapID: swapID, fundingIntentID: KeyPair.generate()!.publicKey) : self
        }

        fileprivate init?(stored data: Data) {
            switch data.count {
            case 32:
                guard let swapID = SwapId(data: data) else { return nil }
                self.init(swapID: swapID, fundingIntentID: nil)
            case 64:
                guard let swapID = SwapId(data: Data(data.prefix(32))),
                      let fundingIntentID = try? PublicKey(Data(data.suffix(32))) else { return nil }
                self.init(swapID: swapID, fundingIntentID: fundingIntentID)
            default:
                return nil
            }
        }
    }

    /// A leg kept for a request.
    struct KeptLeg: Equatable {
        /// The mint (base58) the leg converts out of.
        let source: String
        /// The mint (base58) the leg converts into. Nil for a leg stored before destinations were
        /// kept, which matches no plan's leg.
        let destination: String?
        let ids: LegIDs
    }

    /// The ids the leg converting `source` into `destination` started under for `requestID`, if its
    /// swap is pending.
    func legIDs(for requestID: PaymentRequestID, source: String, destination: String) -> LegIDs? {
        swaps[Self.key(requestID, source, destination)].flatMap(LegIDs.init(stored:))
    }

    /// The swap id the leg converting `source` into `destination` started for `requestID`, if one
    /// is pending.
    func swapID(for requestID: PaymentRequestID, source: String, destination: String) -> SwapId? {
        legIDs(for: requestID, source: source, destination: destination)?.swapID
    }

    /// Every leg kept for `requestID`, whatever it converts, ordered by source then destination.
    func keptLegs(for requestID: PaymentRequestID) -> [KeptLeg] {
        let prefix = Self.prefix(requestID)
        return swaps
            .compactMap { key, data -> KeptLeg? in
                guard key.hasPrefix(prefix), let ids = LegIDs(stored: data) else { return nil }
                // "source" for a leg stored before destinations were kept, else "source|destination".
                let pair = key.dropFirst(prefix.count).split(separator: "|", omittingEmptySubsequences: false)
                switch pair.count {
                case 1: return KeptLeg(source: String(pair[0]), destination: nil, ids: ids)
                case 2: return KeptLeg(source: String(pair[0]), destination: String(pair[1]), ids: ids)
                default: return nil
                }
            }
            .sorted { ($0.source, $0.destination ?? "") < ($1.source, $1.destination ?? "") }
    }

    /// Every leg out of `source` kept for `requestID`, whatever it converts into.
    func keptLegs(for requestID: PaymentRequestID, source: String) -> [KeptLeg] {
        keptLegs(for: requestID).filter { $0.source == source }
    }

    /// Records a leg's ids before its swap starts, so an attempt that dies mid-swap leaves both behind.
    func setLegIDs(_ ids: LegIDs, for requestID: PaymentRequestID, source: String, destination: String) {
        var swaps = swaps
        swaps[Self.key(requestID, source, destination)] = ids.stored
        self.swaps = swaps
    }

    /// Forgets a leg's swap once it is terminal, so a later leg for the same pair gets its own id.
    /// A nil `destination` names a leg stored before destinations were kept.
    func removeSwapID(for requestID: PaymentRequestID, source: String, destination: String?) {
        var swaps = swaps
        swaps[destination.map { Self.key(requestID, source, $0) } ?? Self.key(requestID, source)] = nil
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

    /// The key a leg stored before destinations were kept is under.
    private static func key(_ requestID: PaymentRequestID, _ source: String) -> String {
        prefix(requestID) + source
    }

    private static func key(_ requestID: PaymentRequestID, _ source: String, _ destination: String) -> String {
        "\(key(requestID, source))|\(destination)"
    }
}
