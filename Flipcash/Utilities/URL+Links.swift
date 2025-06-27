//
//  URL+Links.swift
//  Code
//
//  Created by Dima Bart on 2021-11-18.
//

import UIKit
import FlipcashCore

extension URL {
    static func login(with mnemonic: MnemonicPhrase) -> URL {
        URL(string: "https://app.flipcash.com/login/#/e=\(mnemonic.base58EncodedEntropy)")!
    }
    
    static func cashLink(with mnemonic: MnemonicPhrase) -> URL {
        URL(string: "https://send.flipcash.com/c/#/e=\(mnemonic.base58EncodedEntropy)")!
    }
    
    static func poolLink(rendezvous: KeyPair) -> URL {
        URL(string: "https://fun.flipcash.com/p/#/e=\(rendezvous.seed!.base58)")!
    }
    
    static var privacyPolicy: URL {
        URL(string: "https://www.flipcash.com/privacy")!
    }
    
    static var termsOfService: URL {
        URL(string: "https://www.flipcash.com/terms")!
    }
    
    static var settings: URL {
        URL(string: UIApplication.openSettingsURLString)!
    }
}

extension URL {
    
    @available(iOSApplicationExtension, unavailable)
    @MainActor
    static func openSettings() {
        URL.settings.openWithApplication()
    }
    
    @available(iOSApplicationExtension, unavailable)
    @MainActor
    func canOpen() -> Bool {
        UIApplication.shared.canOpenURL(self)
    }
    
    @available(iOSApplicationExtension, unavailable)
    @MainActor
    func openWithApplication() {
        if canOpen() {
            UIApplication.shared.open(self, options: [:], completionHandler: nil)
        }
    }
}
