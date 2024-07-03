//
//  Chat+Extensions.swift
//  Code
//
//  Created by Dima Bart on 2024-02-09.
//

import Foundation
import CodeServices

extension Chat {
    public var localizedTitle: String {
        title
//        switch title {
//        case .domain(let domain):
//            return domain.displayTitle
//        case .localized(let key):
//            return key.localizedStringByKey
//        case .none:
//            return "Anonymous"
//        }
    }
    
    public var previewMessage: String {
        guard let contents = newestMessage?.contents else {
            return "No content"
        }
        
        var filtered = contents.filter {
            if case .localized = $0 {
                true
            } else {
                false
            }
        }
            
        if filtered.isEmpty {
            filtered = contents
        }
        
        return filtered.map { $0.localizedText }.joined(separator: " ")
    }
}

extension Chat.Content {
    public var localizedText: String {
        switch self {
        case .localized(let key):
            return key.localizedStringByKey
            
        case .kin(let genericAmount, let verb):
            let amount: String
            
            switch genericAmount {
            case .exact(let kinAmount):
                amount = kinAmount.kin.formattedFiat(rate: kinAmount.rate, showOfKin: true)
                
            case .partial(let fiat):
                amount = fiat.formatted(showOfKin: true)
            }
            
            return "\(verb.localizedText) \(amount)"
            
        case .sodiumBox:
            return "<! encrypted content !>"
            
        case .text(let text):
            return text
            
        case .thankYou(let direction):
            // TODO: Identify who's thanking who
            return "Thank you"
//            switch direction {
//            case .sent:
//                return "🙏 You thanked them for their tip"
//            case .received:
//                return "🙏 They thanked you for your tip"
//            }
            
        case .identityRevealed(let memberID, let identity):
            return "Identity Revealed"
        }
    }
}

extension Chat.Verb {
    public var localizedText: String {
        switch self {
        case .unknown:
            return Localized.Title.unknown
        case .gave:
            return Localized.Subtitle.youGave
        case .received:
            return Localized.Subtitle.youReceived
        case .withdrew:
            return Localized.Subtitle.youWithdrew
        case .deposited:
            return Localized.Subtitle.youDeposited
        case .sent:
            return Localized.Subtitle.youSent
        case .returned:
            return Localized.Subtitle.wasReturnedToYou
        case .spent:
            return Localized.Subtitle.youSpent
        case .paid:
            return Localized.Subtitle.youPaid
        case .purchased:
            return Localized.Subtitle.youPurchased
        case .tipReceived:
            return Localized.Subtitle.someoneTippedYou
        case .tipSent:
            return Localized.Subtitle.youTipped
        }
    }
}
