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

    /// The public page that opens this user's tipcard.
    ///
    /// Both forms sit at the root — a claimed handle, or the lowercase user id
    /// when there isn't one — with no `/tip/` segment and no `@`, so the link
    /// reads as a name as soon as its owner claims one and the shape of the URL
    /// doesn't change when they do. Both platforms build it here and only here,
    /// on the apex host: its `apple-app-site-association` ends in a `/*`
    /// component, so a bare handle opens the app, and the marketing pages the
    /// app itself links to are excluded there by path.
    static func tipcard(for userID: UserID, username: Username?) -> URL {
        let host = "https://flipcash.com"
        if let username {
            return URL(string: "\(host)/\(username.value)")!
        }
        return URL(string: "\(host)/\(userID.uuidString.lowercased())")!
    }

    /// The invite link for a group chat — the only way into one, since a group
    /// is not otherwise discoverable.
    ///
    /// There is no RPC that mints or resolves one: the link is built from the
    /// chat's own id, whose group form is a UUID, and `Route` parses it back.
    /// `app.flipcash.com` is covered by the associated-domains entitlement, so
    /// the link opens the app rather than the web page when it is installed.
    nonisolated static func groupChatInvite(for conversationID: ConversationID) -> URL {
        URL(string: "https://app.flipcash.com/chat/\(conversationID.linkPathComponent)")!
    }

    /// The in-app link a chat opens through, for the push tap that has no `target_url` to follow.
    ///
    /// The same id an invite link carries, routed the same way, so a group the user has not joined
    /// lands on the gated screen from either entry point. `sendCash` picks the notification action's
    /// destination instead of the transcript.
    nonisolated static func chatDeepLink(for conversationID: ConversationID, sendCash: Bool = false) -> URL {
        let base = "flipcash://chat/\(conversationID.linkPathComponent)"
        return URL(string: sendCash ? "\(base)/send" : base)!
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
    
    static var appStoreApplicationHome: URL {
        URL(string: "https://apps.apple.com/app/flipcash/id6758636374")!
    }

    static var downloadApp: URL {
        URL(string: "https://www.flipcash.com/download")!
    }
}

extension URL {
    
    @available(iOSApplicationExtension, unavailable)
    static func openSettings() {
        URL.settings.openWithApplication()
    }

    @available(iOSApplicationExtension, unavailable)
    static func openMail() {
        URL.mail.openWithApplication()
    }

    @available(iOSApplicationExtension, unavailable)
    func canOpen() -> Bool {
        UIApplication.shared.canOpenURL(self)
    }

    @available(iOSApplicationExtension, unavailable)
    func openWithApplication() {
        if canOpen() {
            UIApplication.shared.open(self, options: [:], completionHandler: nil)
        }
    }
}

extension URL {
    func queryItemValue(for key: String) -> String? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?.first(where: { $0.name == key })?.value
    }
}

extension URL {
    /// Returns the URL stripped of all query parameters and
    /// fragments for safe use in analytics and logging.
    var sanitizedForAnalytics: String {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        components?.queryItems = nil
        return components?.string ?? path
    }
}
