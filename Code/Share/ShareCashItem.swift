//
//  ShareCashItem.swift
//  Code
//
//  Created by Dima Bart on 2023-05-03.
//

import UIKit
import CodeServices
import LinkPresentation

class ShareCashItem: NSObject, UIActivityItemSource {
    
    let giftCard: GiftCardAccount
    let amount: KinAmount
    
    private let formattedAmount: String
    private let content: String
    private let subject: String
    private let shareSheetTitle: String
    
    // MARK: - Init -
    
    init(giftCard: GiftCardAccount, amount: KinAmount) {
        self.giftCard = giftCard
        self.amount = amount
        
        self.formattedAmount = amount.kin.formattedFiat(rate: amount.rate, showOfKin: true)
        self.content = "\(formattedAmount) \(giftCard.url.absoluteString)"
        self.subject = Localized.Subtitle.remoteSendSubject(formattedAmount)
        self.shareSheetTitle = Localized.Subtitle.remoteSendShareSheetTitle(formattedAmount)
        
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
            return giftCard.url
        default:
            break
        }
        
        switch activityType {
        case .airDrop:
            return giftCard.url
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
