//
//  OnrampOperation.swift
//  Flipcash
//

import Foundation
import FlipcashCore

enum OnrampOperation {
    case buy(
        mint: PublicKey,
        displayName: String
    )
    case launch(
        mint: PublicKey,
        displayName: String,
        launchAmount: ExchangedFiat,
        launchFee: ExchangedFiat
    )

    var displayName: String {
        switch self {
        case .buy(_, let displayName):              displayName
        case .launch(_, let displayName, _, _):     displayName
        }
    }

    var logKind: String {
        switch self {
        case .buy:    "buy_existing"
        case .launch: "launch_new"
        }
    }
}
