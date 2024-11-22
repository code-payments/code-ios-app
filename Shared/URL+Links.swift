//
//  URL+Links.swift
//  Code
//
//  Created by Dima Bart on 2021-11-18.
//

import UIKit
import CodeServices

extension URL {
    static func login(with mnemonic: MnemonicPhrase) -> URL {
        URL(string: "https://app.getcode.com/login/#/e=\(mnemonic.base58EncodedEntropy)")!
    }
    
    static func send(with mnemonic: MnemonicPhrase) -> URL {
        URL(string: "https://cash.getcode.com/c/#/e=\(mnemonic.base58EncodedEntropy)")!
    }
    
    static func tipCard(with username: String) -> URL {
        URL(string: "https://tipcard.getcode.com/x/\(username)")!
    }
    
    static var codeHomePage: URL {
        URL(string: "https://www.getcode.com/")!
    }
    
    static var downloadCode: URL {
        URL(string: "https://www.getcode.com/download")!
    }
    
    static var status: URL {
        URL(string: "https://app.getcode.com/status")!
    }
    
    static var privacyPolicy: URL {
        URL(string: "https://app.getcode.com/privacy-policy")!
    }
    
    static var termsOfService: URL {
        URL(string: "https://app.getcode.com/tos")!
    }
    
    static func solanaExplorerTransaction(with signature: Signature) -> URL {
        URL(string: "https://explorer.solana.com/tx/\(signature.base58)")!
    }
    
    static var solanaExplorer: URL {
        URL(string: "https://explorer.solana.com/")!
    }
    
    static func solscanTransaction(with signature: Signature) -> URL {
        URL(string: "https://solscan.io/tx/\(signature.base58)")!
    }
    
    static var videoBuyKin: URL {
        URL(string: "https://www.youtube.com/watch?v=s2aqkF3dJcI")!
    }
    
    static var videoSellKin: URL {
        URL(string: "https://www.youtube.com/watch?v=cyb9Da_mV9I")!
    }
    
    static var settings: URL {
        URL(string: UIApplication.openSettingsURLString)!
    }
    
    static func tweet(content: String) -> URL {
        URL(string: "https://www.twitter.com/intent/tweet?text=\(content)")!
    }
}

extension URL {
    static func codeScheme(path: String = "") -> URL {
        URL(string: "codewallet://\(path)")!
    }
}

extension URL {
    enum DownloadCodeRef {
        case iosQR
        case iosLink
        
        var string: String {
            switch self {
            case .iosQR:   return "iqr"
            case .iosLink: return "is"
            }
        }
    }
    
    static func downloadCode(ref: DownloadCodeRef) -> URL {
        return URL(string: "https://getcode.com/d?ref=\(ref.string)")!
    }
}
    
// MARK: - TestFlight -
    
extension URL {
    static var testFlight: URL {
        URL(string: "itms-beta://")!
    }
    
    static var testFlightAppURL: URL {
        URL(string: "https://beta.itunes.apple.com/v1/app/1562384846")!
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
