//
//  KinAmount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct KinAmount: Equatable, Hashable, Codable {
    
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
