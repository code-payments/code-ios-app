//
//  KinAmount.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct KinAmount: Equatable, Hashable, Codable, Sendable {
    
    public let kin: Kin
    public let fiat: Decimal
    public let rate: Rate
    
    // MARK: - Init -
    
    private init(kin: Kin, fiat: Decimal, rate: Rate) {
        self.kin = kin
        self.fiat = fiat
        self.rate = rate
    }
    
    public init(kin: Kin, rate: Rate) {
        self.init(
            kin: kin,
            fiat: kin.toFiat(fx: rate.fx),
            rate: rate
        )
    }

    public init(fiat: Decimal, rate: Rate) {
        self.init(
            kin: Kin.fromFiat(fiat: fiat, fx: rate.fx).inflating(),
            fiat: fiat,
            rate: rate
        )
    }

    public init?(stringAmount: String, rate: Rate) {
        guard let amount = NumberFormatter.decimal(from: stringAmount), amount > 0 else {
            return nil
        }

        self.init(fiat: amount, rate: rate)
    }
    
    // MARK: - Truncation -
    
    public func truncatingQuarks() -> KinAmount {
        KinAmount(
            kin: kin.truncating(),
            fiat: fiat,
            rate: rate
        )
    }
    
    // MARK: - Rates -
    
    public func replacing(rate: Rate) -> KinAmount {
        KinAmount(
            kin: kin,
            rate: rate
        )
    }
}

extension KinAmount {
    public var descriptionDictionary: [String: String] {
        [
            "kin": kin.description,
            "fx": rate.fx.formatted(),
            "fiat": kin.formattedFiat(rate: rate, suffix: nil),
            "currency": rate.currency.rawValue.uppercased(),
        ]
    }
}

extension UUID {
    
    public var bytes: [Byte] {
        let n = uuid
        return [
            n.0, n.1, n.2,  n.3,  n.4,  n.5,  n.6,  n.7,
            n.8, n.9, n.10, n.11, n.12, n.13, n.14, n.15,
        ]
    }
    
    public var data: Data {
        Data(bytes)
    }
    
    public func generateBlockchainMemo() -> String {
        let type:    Byte = 1
        let version: Byte = 0
        let flags: UInt32 = 0
        
        var data = Data()
        
        data.append(contentsOf: type.bytes)
        data.append(contentsOf: version.bytes)
        data.append(contentsOf: flags.bytes)
        
        data.append(self.data)
        
        return Base58.fromBytes(data.bytes)
    }
}
