//
//  Activity.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-23.
//

import Foundation
import FlipcashCoreAPI

public struct Activity: Identifiable, Sendable, Equatable, Hashable {
    public let id: PublicKey
    public let state: State
    public let kind: Kind
    public let title: String
    public let exchangedFiat: ExchangedFiat
    public let date: Date
    public let metadata: Metadata?
    
    public var cancellableCashLinkMetadata: CashLinkMetadata? {
        switch state {
        case .pending:
            if case .cashLink(let cashLinkMetadata) = metadata, cashLinkMetadata.canCancel {
                return cashLinkMetadata
            }
            
        case .completed, .unknown:
            break
        }
        
        return nil
    }
    
    public init(id: PublicKey, state: State, kind: Kind, title: String, exchangedFiat: ExchangedFiat, date: Date, metadata: Metadata?) {
        self.id = id
        self.state = state
        self.kind = kind
        self.title = title
        self.exchangedFiat = exchangedFiat
        self.date = date
        self.metadata = metadata
    }
}

// MARK: - Kind -

extension Activity {
    public enum Kind: Int, Sendable {
        case welcomeBonus = 0
        case gave         = 1
        case received     = 2
        case withdrew     = 3
        case cashLink     = 4
        case deposited    = 5
        case paid         = 6
        case distributed  = 7
        case unknown
    }
}

// MARK: - Kind -

extension Activity {
    public enum State: Int, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case unknown   = 0
        case pending   = 1
        case completed = 2
        
        public var description: String {
            switch self {
            case .unknown:   "Unknown"
            case .pending:   "Pending"
            case .completed: "Completed"
            }
        }
        
        public var debugDescription: String {
            description
        }
    }
}

extension Activity {
    public enum Metadata: Sendable, Equatable, Hashable {
        case cashLink(CashLinkMetadata)
    }
}

// MARK: - Proto -

extension Activity {
    init(_ proto: Flipcash_Activity_V1_Notification) throws {
        self.init(
            id: PublicKey(proto.id.value)!,
            state: .init(rawValue: proto.state.rawValue) ?? .unknown,
            kind: .init(proto.additionalMetadata),
            title: proto.localizedText,
            exchangedFiat: try ExchangedFiat(proto.paymentAmount),
            date: proto.ts.date,
            metadata: .init(proto.additionalMetadata)
        )
    }
}

extension Activity.Kind {
    init(_ proto: Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata?) {
        if let proto {
            switch proto {
            case .welcomeBonus:
                self = .welcomeBonus
            case .gaveUsdc:
                self = .gave
            case .receivedUsdc:
                self = .received
            case .withdrewUsdc:
                self = .withdrew
            case .sentUsdc:
                self = .cashLink
            case .depositedUsdc:
                self = .deposited
            case .paidUsdc:
                self = .paid
            case .distributedUsdc:
                self = .distributed
            }
            
        } else {
            self = .unknown
        }
    }
}

extension Activity.Metadata {
    init?(_ proto: Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata?) {
        if let proto {
            switch proto {
            case .welcomeBonus, .gaveUsdc, .receivedUsdc, .withdrewUsdc, .depositedUsdc, .paidUsdc, .distributedUsdc:
                return nil
            case .sentUsdc(let metadata):
                self = .cashLink(.init(metadata))
            }
            
        } else {
            return nil
        }
    }
}
