//
//  Activity.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-23.
//

import Foundation
import FlipcashCoreAPI

public struct Activity: Identifiable, Sendable, Equatable, Hashable {
    public let id: ID
    public let title: String
    public let exchangedFiat: ExchangedFiat
    public let date: Date
    public let kind: Kind
}

// MARK: - Kind -

extension Activity {
    public enum Kind: Sendable, Equatable, Hashable {
        case welcomeBonus
        case gave
        case received
        case withdrew
        case cashLink(CashLinkMetadata)
        case unknown
    }
}

// MARK: - Proto -

extension Activity {
    init(_ proto: Flipcash_Activity_V1_Notification) throws {
        self.id            = ID(data: proto.id.value)
        self.title         = proto.localizedText
        self.exchangedFiat = try ExchangedFiat(proto.paymentAmount)
        self.date          = proto.ts.date
        self.kind          = .init(proto.additionalMetadata)
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
            case .sentUsdc(let metadata):
                self = .cashLink(.init(metadata))
            }
            
        } else {
            self = .unknown
        }
    }
}
