//
//  Chat+Localized.swift
//  Code
//
//  Created by Dima Bart on 2024-10-23.
//

import FlipchatServices

extension Chat.Content {
    public var localizedText: String {
        switch self {
        case .localized(let key):
            return key.localizedStringByKey
            
//        case .kin(let genericAmount, let verb, _):
//            let amount: String
//            
//            switch genericAmount {
//            case .exact(let kinAmount):
//                amount = kinAmount.kin.formattedFiat(rate: kinAmount.rate, showOfKin: true)
//                
//            case .partial(let fiat):
//                amount = fiat.formatted(showOfKin: true)
//            }
//            
//            return "\(verb.localizedText) \(amount)"
            
        case .sodiumBox:
            return "<! encrypted content !>"
            
        case .text(let text):
            return text
        }
    }
}
