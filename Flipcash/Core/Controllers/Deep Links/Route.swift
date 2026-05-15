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
        if components.scheme == "flipcash", let host = components.host {
            // Deep link: combine host + path
            normalizedPath = "/\(host)\(components.path)"
        } else {
            // Universal link: use path directly
            normalizedPath = components.path
        }

        guard let path = Path.parse(path: normalizedPath) else {
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
        case give
        case wallet
        case discover
        case unknown(String)
        
        static func parse(path: String) -> Path? {
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
            case "give":
                return .give
            case "wallet":
                // Plain `/wallet` is the home-screen quick-action target.
                // `/wallet/walletConnected` and `/wallet/transactionSigned`
                // (with optional `errorCode`) are Phantom deep-link returns
                // consumed by `WalletConnection.didReceiveURL` — fall
                // through to `.unknown` so the deep-link router skips them.
                return components.count == 1 ? .wallet : .unknown(url.lastPathComponent)
            case "discover":
                return .discover
            default:
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
        case payload = "p"
        case key     = "k" // (Unused)
        case data    = "d" // (Unused)
    }
}
