//
//  GroupPaymentRequest.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// Server-assigned id of a payment request. See `paymentrequest.v1.PaymentRequestId`.
public struct PaymentRequestID: Hashable, Sendable {

    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(_ proto: Flipcash_Paymentrequest_V1_PaymentRequestId) {
        self.data = proto.value
    }

    public var proto: Flipcash_Paymentrequest_V1_PaymentRequestId {
        .with { $0.value = data }
    }
}

/// A request for members of a group chat to pay: shares of a bill (a ``Split``), or a fixed amount
/// from any number of members (a ``Collection``). See `paymentrequest.v1.PaymentRequestMetadata`.
public struct GroupPaymentRequest: Hashable, Sendable {

    public enum Status: Hashable, Sendable {
        case open
        case completed
        case closed
        case expired
        /// A status this build doesn't know, or one the server left unset.
        case unknown
    }

    /// The request's title and description. A private group sends them encrypted with the chat key.
    public enum Text: Hashable, Sendable {
        case plaintext(title: String, description: String)
        case encrypted(scheme: Int, nonce: Data, ciphertext: Data)
    }

    /// How a share was settled, or a payer paid.
    public enum Settlement: Hashable, Sendable {
        /// Paid through a payment intent.
        case intent(Data)
        /// The creator marked it paid.
        case manual
        /// The creator's own share, created paid.
        case creator
        /// A settlement this build doesn't know.
        case unknown
    }

    public struct Share: Hashable, Sendable {
        public let userID: UserID?
        /// The share's amount in the split's ``Split/currency``.
        public let nativeAmount: Double
        /// Set once the share is paid; `nil` while it is owed.
        public let paidAt: Date?
        public let settlement: Settlement?

        public var isPaid: Bool { settlement != nil }

        /// Creates a share; a share built for `CreatePaymentRequest` leaves `paidAt` and `settlement` unset.
        public init(userID: UserID?, nativeAmount: Double, paidAt: Date? = nil, settlement: Settlement? = nil) {
            self.userID = userID
            self.nativeAmount = nativeAmount
            self.paidAt = paidAt
            self.settlement = settlement
        }
    }

    /// An even or custom division of a bill across group members.
    public struct Split: Hashable, Sendable {
        public let text: Text?
        /// The currency code the shares are denominated in.
        public let currency: String
        /// The contract requires one for a split; like a collection's, `nil` reads as never expiring.
        public let endsAt: Date?
        public let shares: [Share]

        /// Creates a split from its text, currency, deadline and shares.
        public init(text: Text?, currency: String, endsAt: Date?, shares: [Share]) {
            self.text = text
            self.currency = currency
            self.endsAt = endsAt
            self.shares = shares
        }
    }

    /// A fixed amount collected from any number of group members, each paying once. See
    /// `paymentrequest.v1.Collection`. How many have paid is in ``GroupPaymentRequest/payerSummary``.
    public struct Collection: Hashable, Sendable {

        /// The one amount every contribution pays, in the collection's ``Collection/currency``.
        public struct FixedAmount: Hashable, Sendable {
            public let nativeAmount: Double

            public init(nativeAmount: Double) {
                self.nativeAmount = nativeAmount
            }
        }

        /// What each contribution must be.
        public enum PaymentAmount: Hashable, Sendable {
            case fixed(FixedAmount)
        }

        public let text: Text?
        /// The currency code the payment amount, and every contribution, is in.
        public let currency: String
        /// When the collection stops taking contributions; `nil` means it never expires and stays
        /// open until the creator closes it.
        public let endsAt: Date?
        /// `nil` for an amount kind this build doesn't know.
        public let paymentAmount: PaymentAmount?

        /// Creates a collection from its text, currency, deadline and payment amount.
        public init(text: Text?, currency: String, endsAt: Date?, paymentAmount: PaymentAmount?) {
            self.text = text
            self.currency = currency
            self.endsAt = endsAt
            self.paymentAmount = paymentAmount
        }
    }

    /// A member asked to pay into a request, or who paid into it. See `paymentrequest.v1.Payer`.
    public struct Payer: Hashable, Sendable {

        public enum Status: Hashable, Sendable {
            /// Something is due and nothing is paid.
            case unpaid
            /// Paid; `paidAt` is `nil` when the server left it unset.
            case paid(paidAt: Date?, settlement: Settlement)
        }

        public let userID: UserID?
        /// What is due from the member: their share's amount for a split, 0 for a collection.
        public let nativeAmountDue: Double
        /// What the member has paid: their share's amount once it is paid for a split, the fixed
        /// amount once they have contributed to a collection.
        public let nativeAmountPaid: Double
        /// `nil` for a status this build doesn't know, or one the server left unset.
        public let status: Status?

        public var isPaid: Bool {
            if case .paid = status { return true }
            return false
        }

        public init(userID: UserID?, nativeAmountDue: Double, nativeAmountPaid: Double, status: Status?) {
            self.userID = userID
            self.nativeAmountDue = nativeAmountDue
            self.nativeAmountPaid = nativeAmountPaid
            self.status = status
        }
    }

    /// Totals over a request's payers, for showing progress without listing them. See
    /// `paymentrequest.v1.PayerSummary`.
    public struct PayerSummary: Hashable, Sendable {
        /// How many payers the request has, paid and unpaid.
        public let payerCount: Int
        /// How many of them have paid.
        public let paidCount: Int
        /// The sum of what is due: a split's whole total, the creator's share included; 0 for a collection.
        public let nativeAmountDue: Double
        /// The sum of what has been paid, hand marks and the creator's own share included.
        public let nativeAmountPaid: Double

        public init(payerCount: Int, paidCount: Int, nativeAmountDue: Double, nativeAmountPaid: Double) {
            self.payerCount = payerCount
            self.paidCount = paidCount
            self.nativeAmountDue = nativeAmountDue
            self.nativeAmountPaid = nativeAmountPaid
        }
    }

    public let id: PaymentRequestID
    public let creator: UserID?
    public let createdAt: Date?
    public let status: Status
    public let closedAt: Date?
    /// Advances by one on every change; a live update applies only on top of the version before it.
    public let version: UInt64
    public let chatID: ConversationID?
    /// Set when the request is a split; `nil` for a collection or a kind this build doesn't know.
    public let split: Split?
    /// Set when the request is a collection; `nil` for a split or a kind this build doesn't know.
    public let collection: Collection?
    /// Totals over the request's payers; `nil` when the server left it unset.
    public let payerSummary: PayerSummary?

    /// Creates a request from its fields; the app builds these only in tests and previews.
    public init(
        id: PaymentRequestID,
        creator: UserID?,
        createdAt: Date?,
        status: Status,
        closedAt: Date?,
        version: UInt64,
        chatID: ConversationID?,
        split: Split?,
        collection: Collection? = nil,
        payerSummary: PayerSummary? = nil
    ) {
        self.id = id
        self.creator = creator
        self.createdAt = createdAt
        self.status = status
        self.closedAt = closedAt
        self.version = version
        self.chatID = chatID
        self.split = split
        self.collection = collection
        self.payerSummary = payerSummary
    }

    /// When the request stops taking payments, whichever kind it is; `nil` means it never expires.
    public var endsAt: Date? {
        split?.endsAt ?? collection?.endsAt
    }
}

extension GroupPaymentRequest.Status {
    init(_ proto: Flipcash_Paymentrequest_V1_PaymentRequestStatus) {
        switch proto {
        case .open:                  self = .open
        case .completed:             self = .completed
        case .closed:                self = .closed
        case .expired:               self = .expired
        case .unknown, .UNRECOGNIZED: self = .unknown
        }
    }
}

extension GroupPaymentRequest {
    init?(_ proto: Flipcash_Paymentrequest_V1_PaymentRequestMetadata) {
        guard proto.hasPaymentRequestID else { return nil }

        var chatID: ConversationID?
        var split: Split?
        var collection: Collection?
        switch proto.kind {
        case .groupChat(let group):
            chatID = group.hasChatID ? ConversationID(group.chatID) : nil
            switch group.type {
            case .split(let value):      split = Split(value)
            case .collection(let value): collection = Collection(value)
            case nil:                    break
            }
        case nil:
            break
        }

        self.init(
            id: PaymentRequestID(proto.paymentRequestID),
            creator: proto.hasCreator ? try? UUID(data: proto.creator.value) : nil,
            createdAt: proto.hasCreatedAt ? proto.createdAt.date : nil,
            status: Status(proto.status),
            closedAt: proto.hasClosedAt ? proto.closedAt.date : nil,
            version: proto.version,
            chatID: chatID,
            split: split,
            collection: collection,
            payerSummary: proto.hasPayerSummary ? PayerSummary(proto.payerSummary) : nil
        )
    }
}

extension GroupPaymentRequest.Text {
    init(_ proto: Flipcash_Paymentrequest_V1_PaymentRequestText) {
        self = .plaintext(title: proto.title, description: proto.description_p)
    }

    init(_ proto: Flipcash_Paymentrequest_V1_EncryptedPaymentRequestText) {
        self = .encrypted(scheme: proto.scheme.rawValue, nonce: proto.nonce, ciphertext: proto.ciphertext)
    }
}

extension GroupPaymentRequest.Split {
    init(_ proto: Flipcash_Paymentrequest_V1_Split) {
        let text: GroupPaymentRequest.Text?
        switch proto.text {
        case .plaintext(let value): text = .init(value)
        case .encrypted(let value): text = .init(value)
        case nil:                   text = nil
        }
        self.init(
            text: text,
            currency: proto.currency,
            endsAt: proto.hasEndsAt ? proto.endsAt.date : nil,
            shares: proto.shares.map(GroupPaymentRequest.Share.init)
        )
    }
}

extension GroupPaymentRequest.Collection {
    init(_ proto: Flipcash_Paymentrequest_V1_Collection) {
        let text: GroupPaymentRequest.Text?
        switch proto.text {
        case .plaintext(let value): text = .init(value)
        case .encrypted(let value): text = .init(value)
        case nil:                   text = nil
        }
        let paymentAmount: PaymentAmount?
        switch proto.paymentAmount {
        case .fixed(let fixed): paymentAmount = .fixed(FixedAmount(nativeAmount: fixed.nativeAmount))
        case nil:               paymentAmount = nil
        }
        self.init(
            text: text,
            currency: proto.currency,
            endsAt: proto.hasEndsAt ? proto.endsAt.date : nil,
            paymentAmount: paymentAmount
        )
    }
}

extension GroupPaymentRequest.Settlement {
    /// How a `Paid` (a paid share, or a paid payer) was settled.
    init(_ proto: Flipcash_Paymentrequest_V1_Paid) {
        switch proto.how {
        case .intent(let intent): self = .intent(intent.value)
        case .manual:             self = .manual
        case .creator:            self = .creator
        case nil:                 self = .unknown
        }
    }
}

extension GroupPaymentRequest.Share {
    init(_ proto: Flipcash_Paymentrequest_V1_Share) {
        self.init(
            userID: proto.hasUserID ? try? UUID(data: proto.userID.value) : nil,
            nativeAmount: proto.nativeAmount,
            paidAt: proto.hasPaid && proto.paid.hasPaidAt ? proto.paid.paidAt.date : nil,
            settlement: proto.hasPaid ? GroupPaymentRequest.Settlement(proto.paid) : nil
        )
    }
}

extension GroupPaymentRequest.Payer {
    init(_ proto: Flipcash_Paymentrequest_V1_Payer) {
        let status: Status?
        switch proto.status {
        case .unpaid:
            status = .unpaid
        case .paid(let paid):
            status = .paid(paidAt: paid.hasPaidAt ? paid.paidAt.date : nil, settlement: GroupPaymentRequest.Settlement(paid))
        case nil:
            status = nil
        }
        self.init(
            userID: proto.hasUserID ? try? UUID(data: proto.userID.value) : nil,
            nativeAmountDue: proto.nativeAmountDue,
            nativeAmountPaid: proto.nativeAmountPaid,
            status: status
        )
    }
}

extension GroupPaymentRequest.PayerSummary {
    init(_ proto: Flipcash_Paymentrequest_V1_PayerSummary) {
        self.init(
            payerCount: Int(proto.payerCount),
            paidCount: Int(proto.paidCount),
            nativeAmountDue: proto.nativeAmountDue,
            nativeAmountPaid: proto.nativeAmountPaid
        )
    }
}

// MARK: - Wire form -

extension GroupPaymentRequest.Text {
    var proto: Flipcash_Paymentrequest_V1_Split.OneOf_Text {
        switch self {
        case .plaintext(let title, let description):
            .plaintext(Self.plaintext(title: title, description: description))
        case .encrypted(let scheme, let nonce, let ciphertext):
            .encrypted(Self.encrypted(scheme: scheme, nonce: nonce, ciphertext: ciphertext))
        }
    }

    /// The same text as a collection's text arm.
    var collectionProto: Flipcash_Paymentrequest_V1_Collection.OneOf_Text {
        switch self {
        case .plaintext(let title, let description):
            .plaintext(Self.plaintext(title: title, description: description))
        case .encrypted(let scheme, let nonce, let ciphertext):
            .encrypted(Self.encrypted(scheme: scheme, nonce: nonce, ciphertext: ciphertext))
        }
    }

    private static func plaintext(title: String, description: String) -> Flipcash_Paymentrequest_V1_PaymentRequestText {
        .with { $0.title = title; $0.description_p = description }
    }

    private static func encrypted(scheme: Int, nonce: Data, ciphertext: Data) -> Flipcash_Paymentrequest_V1_EncryptedPaymentRequestText {
        .with {
            $0.scheme = .init(rawValue: scheme) ?? .unknown
            $0.nonce = nonce
            $0.ciphertext = ciphertext
        }
    }
}

extension GroupPaymentRequest.Split {
    /// The wire form for `CreatePaymentRequest`. Shares go out unpaid; the server settles the
    /// creator's own share itself.
    var proto: Flipcash_Paymentrequest_V1_Split {
        .with {
            $0.text = text?.proto
            $0.currency = currency
            if let endsAt { $0.endsAt = .init(date: endsAt) }
            $0.shares = shares.compactMap { share in
                guard let userID = share.userID else { return nil }
                return .with {
                    $0.userID = userID.proto
                    $0.nativeAmount = share.nativeAmount
                }
            }
        }
    }
}

extension GroupPaymentRequest {
    /// Which slice of a chat's requests to list.
    public enum Section: Hashable, Sendable {
        /// Requests still collecting payments.
        case open
        /// Completed, closed and expired requests.
        case resolved

        var proto: Flipcash_Paymentrequest_V1_GetChatPaymentRequestsRequest.Section {
            switch self {
            case .open:     .open
            case .resolved: .resolved
            }
        }
    }

    /// Which of a request's payers to list.
    public enum PayerSection: Hashable, Sendable {
        /// Payers who still owe something, in the order the request defines. Always empty for a
        /// collection, where nothing is owed.
        case unpaid
        /// Payers who have paid.
        case paid

        var proto: Flipcash_Paymentrequest_V1_GetPayersRequest.Section {
            switch self {
            case .unpaid: .unpaid
            case .paid:   .paid
            }
        }
    }
}

/// One best-effort, real-time change to a payment request from the chat event stream. See
/// `paymentrequest.v1.PaymentRequestUpdate`.
///
/// Apply rules: `.created` is treated like a fetched copy (keep the greater version). `.updates` at
/// version V against local version L: V <= L is ignored, V == L + 1 applies its updates in order
/// then sets the version, V > L + 1 refetches. A ``Change/Update/unknown`` update, or a share,
/// payer or summary update missing what it carries, also refetches.
public struct DecodedPaymentRequestUpdate: Hashable, Sendable {

    public enum Change: Hashable, Sendable {
        case created(GroupPaymentRequest)
        case updates(version: UInt64, [Update])

        public enum Update: Hashable, Sendable {
            /// A share was paid; the share carries the user it belongs to.
            case sharePaid(GroupPaymentRequest.Share)
            /// The request completed or closed. `closedAt` is `nil` when the server left it unset.
            case statusChanged(GroupPaymentRequest.Status, closedAt: Date?)
            /// A payer as it now stands, after a payment into the request.
            case payerChanged(GroupPaymentRequest.Payer)
            /// The request's payer totals as they now stand.
            case payerSummaryChanged(GroupPaymentRequest.PayerSummary)
            /// An update kind this build doesn't know, or an update missing what it carries.
            case unknown
        }
    }

    public let id: PaymentRequestID
    public let change: Change

    public init(id: PaymentRequestID, change: Change) {
        self.id = id
        self.change = change
    }
}

extension DecodedPaymentRequestUpdate {
    /// Nil when the update has no request id, or its kind (or a `created` copy) isn't one this build can read.
    init?(_ proto: Flipcash_Paymentrequest_V1_PaymentRequestUpdate) {
        guard proto.hasPaymentRequestID else { return nil }
        switch proto.kind {
        case .created(let metadata):
            guard let request = GroupPaymentRequest(metadata) else { return nil }
            self.init(id: PaymentRequestID(proto.paymentRequestID), change: .created(request))
        case .updates(let updates):
            self.init(
                id: PaymentRequestID(proto.paymentRequestID),
                change: .updates(version: updates.version, updates.updates.map(Change.Update.init))
            )
        case nil:
            return nil
        }
    }
}

extension DecodedPaymentRequestUpdate.Change.Update {
    init(_ proto: Flipcash_Paymentrequest_V1_PaymentRequestUpdate.Update) {
        switch proto.kind {
        case .sharePaymentUpdate(let update):
            self = update.hasShare ? .sharePaid(GroupPaymentRequest.Share(update.share)) : .unknown
        case .statusUpdate(let update):
            self = .statusChanged(
                GroupPaymentRequest.Status(update.status),
                closedAt: update.hasClosedAt ? update.closedAt.date : nil
            )
        case .payerUpdate(let update):
            self = update.hasPayer ? .payerChanged(GroupPaymentRequest.Payer(update.payer)) : .unknown
        case .payerSummaryUpdate(let update):
            self = update.hasPayerSummary ? .payerSummaryChanged(GroupPaymentRequest.PayerSummary(update.payerSummary)) : .unknown
        case nil:
            self = .unknown
        }
    }
}
