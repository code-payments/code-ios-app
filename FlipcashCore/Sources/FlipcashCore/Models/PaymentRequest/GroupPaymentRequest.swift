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

/// A request for members of a group chat to pay shares of a bill. See
/// `paymentrequest.v1.PaymentRequestMetadata`.
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

    /// How a share was settled.
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
    }

    /// An even or custom division of a bill across group members.
    public struct Split: Hashable, Sendable {
        public let text: Text?
        /// The currency code the shares are denominated in.
        public let currency: String
        public let endsAt: Date?
        public let shares: [Share]
    }

    public let id: PaymentRequestID
    public let creator: UserID?
    public let createdAt: Date?
    public let status: Status
    public let closedAt: Date?
    /// Advances on every change; apply the greater value, since there are no events to drive a refetch.
    public let version: UInt64
    public let chatID: ConversationID?
    /// `nil` for a request kind this build doesn't know.
    public let split: Split?
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
        switch proto.kind {
        case .groupChat(let group):
            chatID = group.hasChatID ? ConversationID(group.chatID) : nil
            switch group.type {
            case .split(let value): split = Split(value)
            case nil:               break
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
            split: split
        )
    }
}

extension GroupPaymentRequest.Split {
    init(_ proto: Flipcash_Paymentrequest_V1_Split) {
        let text: GroupPaymentRequest.Text?
        switch proto.text {
        case .plaintext(let value):
            text = .plaintext(title: value.title, description: value.description_p)
        case .encrypted(let value):
            text = .encrypted(scheme: value.scheme.rawValue, nonce: value.nonce, ciphertext: value.ciphertext)
        case nil:
            text = nil
        }
        self.init(
            text: text,
            currency: proto.currency,
            endsAt: proto.hasEndsAt ? proto.endsAt.date : nil,
            shares: proto.shares.map(GroupPaymentRequest.Share.init)
        )
    }
}

extension GroupPaymentRequest.Share {
    init(_ proto: Flipcash_Paymentrequest_V1_Share) {
        let settlement: GroupPaymentRequest.Settlement?
        if proto.hasPaid {
            switch proto.paid.how {
            case .intent(let intent): settlement = .intent(intent.value)
            case .manual:             settlement = .manual
            case .creator:            settlement = .creator
            case nil:                 settlement = .unknown
            }
        } else {
            settlement = nil
        }
        self.init(
            userID: proto.hasUserID ? try? UUID(data: proto.userID.value) : nil,
            nativeAmount: proto.nativeAmount,
            paidAt: proto.hasPaid && proto.paid.hasPaidAt ? proto.paid.paidAt.date : nil,
            settlement: settlement
        )
    }
}

// MARK: - Wire form -

extension GroupPaymentRequest.Text {
    var proto: Flipcash_Paymentrequest_V1_Split.OneOf_Text {
        switch self {
        case .plaintext(let title, let description):
            .plaintext(.with { $0.title = title; $0.description_p = description })
        case .encrypted(let scheme, let nonce, let ciphertext):
            .encrypted(.with {
                $0.scheme = .init(rawValue: scheme) ?? .unknown
                $0.nonce = nonce
                $0.ciphertext = ciphertext
            })
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
}
