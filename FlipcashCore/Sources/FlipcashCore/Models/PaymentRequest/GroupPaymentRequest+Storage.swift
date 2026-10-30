//
//  GroupPaymentRequest+Storage.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

// The stored form of a request: its whole `PaymentRequestMetadata`, serialized. The store keeps the
// message rather than columns for its fields because the contract versions and replaces it whole.
// Private-chat text stays in its `.encrypted` form: this model never holds opened text (the chat's
// seal opens it at read time, in ``PaymentRequestText``), so what is encoded is what the server sent.

extension GroupPaymentRequest.Status {
    /// The status's wire number, which the store keeps beside the blob to merge on.
    public var wireValue: Int {
        switch self {
        case .open:      Flipcash_Paymentrequest_V1_PaymentRequestStatus.open.rawValue
        case .completed: Flipcash_Paymentrequest_V1_PaymentRequestStatus.completed.rawValue
        case .closed:    Flipcash_Paymentrequest_V1_PaymentRequestStatus.closed.rawValue
        case .expired:   Flipcash_Paymentrequest_V1_PaymentRequestStatus.expired.rawValue
        case .unknown:   Flipcash_Paymentrequest_V1_PaymentRequestStatus.unknown.rawValue
        }
    }
}

extension GroupPaymentRequest {

    /// The request as a serialized `PaymentRequestMetadata`, paid shares and encrypted text included.
    public func serializedMetadata() throws -> Data {
        try metadataProto.serializedData()
    }

    /// Reads a request back from ``serializedMetadata()``; nil when the bytes don't decode.
    public init?(serializedMetadata: Data) {
        guard let proto = try? Flipcash_Paymentrequest_V1_PaymentRequestMetadata(serializedBytes: serializedMetadata) else {
            return nil
        }
        self.init(proto)
    }

    private var metadataProto: Flipcash_Paymentrequest_V1_PaymentRequestMetadata {
        .with {
            $0.paymentRequestID = id.proto
            if let creator { $0.creator = creator.proto }
            if let createdAt { $0.createdAt = .init(date: createdAt) }
            $0.status = Self.protoStatus(status)
            if let closedAt { $0.closedAt = .init(date: closedAt) }
            $0.version = version
            if let chatID {
                $0.groupChat = .with {
                    $0.chatID = chatID.proto
                    if let split { $0.split = split.storedProto }
                }
            }
        }
    }

    private static func protoStatus(_ status: Status) -> Flipcash_Paymentrequest_V1_PaymentRequestStatus {
        switch status {
        case .open:      .open
        case .completed: .completed
        case .closed:    .closed
        case .expired:   .expired
        case .unknown:   .unknown
        }
    }
}

extension GroupPaymentRequest.Split {
    /// Unlike ``proto``, which is the create request and sends shares unpaid, keeps each share's settlement.
    fileprivate var storedProto: Flipcash_Paymentrequest_V1_Split {
        .with {
            $0.text = text?.proto
            $0.currency = currency
            if let endsAt { $0.endsAt = .init(date: endsAt) }
            $0.shares = shares.map(\.storedProto)
        }
    }
}

extension GroupPaymentRequest.Share {
    fileprivate var storedProto: Flipcash_Paymentrequest_V1_Share {
        .with {
            if let userID { $0.userID = userID.proto }
            $0.nativeAmount = nativeAmount
            guard let settlement else { return }
            $0.paid = .with {
                if let paidAt { $0.paidAt = .init(date: paidAt) }
                switch settlement {
                case .intent(let id): $0.intent = .with { $0.value = id }
                case .manual:         $0.manual = .init()
                case .creator:        $0.creator = .init()
                case .unknown:        break
                }
            }
        }
    }
}
