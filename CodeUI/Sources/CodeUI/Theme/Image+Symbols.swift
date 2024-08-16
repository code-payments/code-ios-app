//
//  Image+Symbols.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

extension Image {
    public static func system(_ systemSymbol: SystemSymbol) -> Image {
        Image(systemName: systemSymbol.rawValue)
    }
    
    public static func symbol(_ name: Symbol) -> Image {
        Image(name.rawValue, bundle: Bundle.module)
    }
    
    public static func asset(_ name: Asset) -> Image  {
        Image(name.rawValue, bundle: Bundle.module)
    }
    
    static func regionFlag(_ region: Region) -> Image  {
        Image(region.rawValue, bundle: Bundle.module)
    }
    
    static func cryptoFlag(_ currency: CurrencyCode) -> Image  {
        Image(currency.rawValue.uppercased(), bundle: Bundle.module)
    }
}

// MARK: - System -

public enum SystemSymbol: String {
    case circleDotted = "circle.dotted"
    case circleCheck = "checkmark.circle.fill"
    case circlePerson = "person.circle"
    
    case arrowUp = "arrow.up"
    case arrowDown = "arrow.down"
    case arrowRight = "arrow.right"
    case arrowLeft = "arrow.left"
    
    case info = "info.circle"
    case doc = "doc.on.doc"
    case clipboard = "doc.on.clipboard"
    case paste = "arrow.turn.left.down"
    case touchID = "touchid"
    case faceID = "faceid"
    
    case chevronDown = "chevron.down"
    case chevronRight = "chevron.right"
    
    case xmark = "xmark.app.fill"
    
    case speakerSlash = "speaker.slash.fill"
    
    case lockDashed = "lock.app.dashed"
}

// MARK: - Symbol -

public enum Symbol: String {
//    case kin = "kin"
//    case kinLarge = "kin.large"
    case code = "code"
    case google = "google"
    case hexSmall = "hex.small.fill"
    case hexLarge = "hex.large.fill"
}

// MARK: - Asset -

public enum Asset: String {
    case close
    case history
    case wallet
    case tipcard
    
    case checkmark
    case checkmarkLarge
    case google = "google.button"
//    case kin = "kin.button"
//    case kinLarge = "kin.button.large"
    case codeBrand
    case codeLogo
    case invites
    case invitesNew = "invites.new"
    case inviteLetter
    case telephoneOutline
    case telephoneFilled
    case graphicCameraAccess
    case graphicPushPermission
    case hamburger
    case deleteBubble
    case graphicWallet
    case youtube
    case videoBuyKin
    case videoSellKin
    case done
    
    // Messaging
    
    case paperplane
    case statusSent
    case statusDelivered
    case statusRead
    
    case kado
    
    // Bill
    
    case globe
    case grid
    case hexagons
    case securityStrip
    case waves
    
    // Icons
    
    case deposit
    case withdraw
    case key
    case phone
    case logout
    case debug
    case switchAccounts
    case faq
    case delete
    case myAccount
    case send
    case send2
    case cancel
    case dollar
    case gift
    case tip
    case settings
    case camera
    case reload
    
    // Third-Party
    
    case twitter
    case twitterBlue
    case twitterGold
    case twitterGrey
    
    case logoApple
    case logoAndroid
}
