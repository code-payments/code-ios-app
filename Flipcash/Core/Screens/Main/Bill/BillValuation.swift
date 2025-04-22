//
//  BillValuation.swift
//  Code
//
//  Created by Dima Bart on 2025-04-21.
//

import Foundation
import FlipcashCore

struct BillValuation: Identifiable {
    
    var id: PublicKey {
        rendezvous
    }
    
    let rendezvous: PublicKey
    let exchangedFiat: ExchangedFiat
    
    init(rendezvous: PublicKey, exchangedFiat: ExchangedFiat) {
        self.rendezvous = rendezvous
        self.exchangedFiat = exchangedFiat
    }
}
