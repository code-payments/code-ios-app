//
//  Route.swift
//  Code
//
//  Created by Dima Bart on 2021-11-18.
//

import Foundation
import FlipcashCore

nonisolated struct Route {

    let path: Path
    let properties: [String: String]
    let fragments: [Fragment.Key: Fragment]

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }

        // Normalize path extraction for both URL types:
        // - Universal Links: https://app.flipcash.com/token/ABC → path = "/token/ABC"
        // - Deep Links: flipcash://token/ABC → host = "token", path = "/ABC"
        //   Need to combine as "/token/ABC"
        let normalizedPath: String
        if components.scheme == Path.customScheme, let host = components.host {
            // Deep link: combine host + path
            normalizedPath = "/\(host)\(components.path)"
        } else {
            // Universal link: use path directly
            normalizedPath = components.path
        }

        guard let path = Path.parse(path: normalizedPath, scheme: components.scheme) else {
            return nil
        }
        
        // 1. Parse any query items into properties
        
        var properties: [String: String] = [:]
        
        components.queryItems?.forEach { queryItem in
            properties[queryItem.name] = queryItem.value ?? ""
        }
        
        // 2. Parse any fragment values into properties
        
        var fragments: [Fragment.Key: Fragment] = [:]
        
        // We need to use the percentEncoded fragment otherwise
        // we'll get partial data if base64 includes a /
        if let urlFragment = url.fragment(percentEncoded: true) {
            let components = urlFragment.components(separatedBy: "/")
            components.forEach { component in
                if let fragment = Route.Fragment(fragmentString: component) {
                    fragments[fragment.key] = fragment
                }
            }
        }
        
        self.path = path
        self.properties = properties
        self.fragments = fragments
    }
    
    init?(userActivity: NSUserActivity) {
        guard
            userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
        else {
            return nil
        }
        
        self.init(url: url)
    }
}

// MARK: - Path -

nonisolated extension Route {
    enum Path {

        case login
        case cash
        case verifyEmail
        case token(PublicKey)
        case chat(ConversationID)
        case chatSendCash(ConversationID)
        /// A tipcard link for a user who hasn't claimed a handle —
        /// `flipcash.com/<userId>`. Also reached by the older `/tip/<userId>`
        /// form, which stays parseable for links already shared.
        case tip(UserID)
        /// A vanity tipcard link — `flipcash.com/<handle>`, no `@`. The same
        /// destination as ``tip(_:)``, reached by the handle its owner claimed
        /// rather than by their user id.
        case username(Username)
        case give
        case balance
        case discover
        case unknown(String)

        /// The app's custom URL scheme, registered in `Info.plist`.
        static let customScheme = "flipcash"

        /// `scheme` separates a home-screen quick action (`flipcash://give`)
        /// from a web link (`app.flipcash.com/give`). Only the custom scheme
        /// carries the quick-action routes; on the web those names are ordinary
        /// path segments, and an unmatched one reads as a handle.
        ///
        /// Host-agnostic by design: `app.flipcash.com/<handle>` and
        /// `flipcash.com/<handle>` are the same link, and which hosts reach the
        /// app at all is the associated-domains entitlement's decision, not
        /// this parser's.
        static func parse(path: String, scheme: String?) -> Path? {
            guard let url = URL(string: path.trimmingCharacters(in: .init(charactersIn: "/"))) else {
                return nil
            }
            
            let components = url.pathComponents
            
            guard !components.isEmpty else {
                return nil
            }
            
            // Handle any paths that use the last path component
            switch components[0] {
            case "login":
                return .login
            case "cash", "c":
                return .cash
            case "verify":
                return .verifyEmail
            case "token":
                guard components.count > 1, let mint = try? PublicKey(base58: components[1]) else {
                    return nil
                }
                return .token(mint)
            case "chat":
                guard components.count > 1 else {
                    return nil
                }
                guard let id = ConversationID(base64URLEncoded: components[1]) else {
                    return nil
                }
                // `/chat/{id}/send` opens the Send Cash sheet over the chat.
                if components.count > 2, components[2] == "send" {
                    return .chatSendCash(id)
                }
                return .chat(id)
            case "tip":
                // The tipcard share URL as it used to be built: `/tip/{userId}`,
                // lowercase UUID. New links put the id at the root instead
                // (below); this stays for the ones already out there.
                guard components.count > 1, let userID = UUID(uuidString: components[1]) else {
                    return nil
                }
                return .tip(userID)
            case "give" where scheme == customScheme:
                return .give
            case "balance" where scheme == customScheme:
                return .balance
            case "wallet":
                // Reserved for Phantom callbacks (consumed by
                // `WalletConnection.didReceiveURL`). Home-screen
                // "Wallet" quick action uses `/balance` instead.
                return .unknown(url.lastPathComponent)
            case "discover" where scheme == customScheme:
                return .discover
            default:
                guard components.count == 1 else {
                    return .unknown(url.lastPathComponent)
                }
                // A single unmatched segment is a tipcard: the user id when its
                // owner has no handle, otherwise the handle itself. A uuid can
                // never be mistaken for a handle — dashes aren't in the handle
                // character set, and 36 characters overruns its length — so the
                // two forms share the root without ambiguity.
                if let userID = UUID(uuidString: components[0]) {
                    return .tip(userID)
                }
                // Lowercased first: handles are stored lowercase, and a link a
                // messaging app auto-capitalized is still the same link.
                // Whether the handle *can* be claimed — the reserved list — is
                // the server's to say, so nothing is filtered out here beyond
                // the routes above.
                if let username = Username(components[0].lowercased()) {
                    return .username(username)
                }
                return .unknown(url.lastPathComponent)
            }
        }
    }
}

// MARK: - Fragment -

nonisolated extension Route {
    struct Fragment {
        
        let key: Key
        let value: String
        
        init?(fragmentString: String) {
            let separator = "="
            for key in Key.allCases {
                let prefix = "\(key.rawValue)\(separator)"
                if fragmentString.hasPrefix(prefix) {
                    let value = String(fragmentString.dropFirst(prefix.count))
                    self.init(
                        key: key,
                        value: value
                    )
                    return
                }
            }
            return nil
        }
        
        init(key: Key, value: String) {
            self.key = key
            self.value = value.removingPercentEncoding ?? value
        }
    }
}

nonisolated extension Route.Fragment {
    enum Key: String, CaseIterable {
        case entropy = "e"
    }
}
