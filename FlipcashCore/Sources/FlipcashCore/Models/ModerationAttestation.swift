//
//  ModerationAttestation.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// A signed moderation proof returned by the Moderation service.
///
/// The wire format is the serialized `Flipcash_Moderation_V1_ModerationAttestation`
/// proto. The `Currency.Launch` RPC accepts it opaquely via
/// `Ocp_Currency_V1_ModerationAttestation`, which wraps the same bytes in a
/// `raw_value` field.
public struct ModerationAttestation: Sendable, Equatable {

    public let rawValue: Data

    public init(rawValue: Data) {
        self.rawValue = rawValue
    }

    public init(_ proto: Flipcash_Moderation_V1_ModerationAttestation) throws {
        self.rawValue = try proto.serializedData()
    }

    public var currencyProto: Ocp_Currency_V1_ModerationAttestation {
        .with { $0.rawValue = rawValue }
    }
}
