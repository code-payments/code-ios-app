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
    
    static func poolLink(rendezvous: KeyPair, info: PoolInfo?) -> URL {
        var infoString: String = ""
        if let info, let encoded = try? Data.base64EncodedPoolInfo(info) {
            infoString = "\(encoded)/"
        }
        
        return URL(string: "https://fun.flipcash.com/p/\(infoString)#/e=\(rendezvous.seed!.base58)")!
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
    
    static var mail: URL {
        URL(string: "message://")!
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
    static func openMail() {
        URL.mail.openWithApplication()
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
