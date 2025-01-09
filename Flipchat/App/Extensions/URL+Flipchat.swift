//
//  URL+Links.swift
//  Code
//
//  Created by Dima Bart on 2021-11-18.
//

import UIKit
import FlipchatServices

extension URL {
    static func flipchatLogin(with mnemonic: MnemonicPhrase) -> URL {
        URL(string: "https://app.flipchat.xyz/login/#/e=\(mnemonic.base58EncodedEntropy)")!
    }
    
    static func flipchatRoom(roomNumber: RoomNumber, messageID: MessageID?) -> URL {
        var components = URLComponents(string: "https://app.flipchat.xyz/room/\(roomNumber)")!
        
        if let messageID {
            components.queryItems?.append(
                URLQueryItem(name: "m", value: messageID.data.hexString())
            )
        }
        
        return components.url!
    }
    
    static var flipchatPrivacyPolicy: URL {
        URL(string: "https://flipchat.xyz/privacy")!
    }
    
    static var flipchatTermsOfService: URL {
        URL(string: "https://flipchat.xyz/terms")!
    }
}

// MARK: - Local -

extension URL {
    // Prev chat.sqlite
    static let chatStoreURL = URL.applicationSupportDirectory.appending(path: "flipchat.sqlite")
}
