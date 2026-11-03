//
//  CashReturn.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// The return state a cash message carries, set by the server when it posts the message and never
/// changed afterwards. Whether the offer is still open is not stored here: it is answered by
/// `FlipClient.getCashMessageReturnStatus`.
public struct CashReturn: Sendable, Equatable, Hashable {

    /// Whether the message offers its receiver a return. Today only the cash message that opened a DM
    /// carries one.
    public let hasOffer: Bool

    /// The message whose payment this message returns. A client that sees it stops offering a
    /// return on that message.
    public let returnOf: ReturnOf?

    /// The cash message a return payment returns.
    public struct ReturnOf: Sendable, Equatable, Hashable {
        public let messageID: MessageID

        public init(messageID: MessageID) {
            self.messageID = messageID
        }
    }

    public init(hasOffer: Bool, returnOf: ReturnOf?) {
        self.hasOffer = hasOffer
        self.returnOf = returnOf
    }
}

extension CashReturn {
    /// The return state of a cash message; `nil` when the message neither offers nor is a return.
    init?(_ proto: Flipcash_Messaging_V1_CashContent) {
        guard proto.hasPaymentReturn else { return nil }
        let payment = proto.paymentReturn
        let returnOf: ReturnOf? = payment.hasReturnOf ? ReturnOf(messageID: MessageID(payment.returnOf.messageID)) : nil
        guard payment.hasOffer || returnOf != nil else { return nil }
        self.init(hasOffer: payment.hasOffer, returnOf: returnOf)
    }
}

/// Where a cash message's return stands, as the server answers `getCashMessageReturnStatus`.
public struct CashReturnStatus: Sendable, Equatable {

    public enum State: Sendable, Equatable {
        /// The payment can still be returned.
        case available
        /// The payment was returned. Terminal: a client may stop asking.
        case returned
        /// A status this client does not know.
        case unknown
    }

    public let state: State

    /// The intent id a return payment must be submitted under, set only for the message's single
    /// receiver. Private to the payment: never log or report it.
    public let paymentIntentID: Data?

    public init(state: State, paymentIntentID: Data?) {
        self.state = state
        self.paymentIntentID = paymentIntentID
    }
}
