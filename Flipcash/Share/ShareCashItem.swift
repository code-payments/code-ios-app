//
//  ShareCashItem.swift
//  Code
//
//  Created by Dima Bart on 2023-05-03.
//

import UIKit
import LinkPresentation
import FlipcashCore

class ShareCashLinkItem: NSObject, UIActivityItemSource {
    
    let giftCard: GiftCardCluster
    let exchangedFiat: ExchangedFiat
    let url: URL
    
    private let formattedAmount: String
    private let content: String
    private let subject: String
    private let shareSheetTitle: String
    
    // MARK: - Init -
    
    init(giftCard: GiftCardCluster, exchangedFiat: ExchangedFiat) {
        self.giftCard      = giftCard
        self.exchangedFiat = exchangedFiat
        self.url           = URL.cashLink(with: giftCard.mnemonic)
        
        self.formattedAmount = exchangedFiat.converted.formatted(suffix: nil)
        self.content         = "\(formattedAmount) \(url.absoluteString)"
        self.subject         = "Here's \(formattedAmount)"
        self.shareSheetTitle = "Send \(formattedAmount)"
        
        super.init()
    }
    
    // MARK: - UIActivityItemSource -
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return ""
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return subject
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        
        guard let activityType else {
            return content
        }
        
        // Handle custom activity types
        switch activityType.rawValue {
        case "com.tinyspeck.chatlyio.share": // Slack
            return url
        case "org.whispersystems.signal.shareextension": // Signal
            return url
        default:
            break
        }
        
        switch activityType {
        case .airDrop:
            return url
        default:
            return content
        }
    }
    
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = shareSheetTitle
        return metadata
    }
}
