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
    static let chatStoreURL = URL.applicationSupportDirectory.appending(path: "rooms.sqlite")
}
