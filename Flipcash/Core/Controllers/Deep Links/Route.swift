//
//  Route.swift
//  Code
//
//  Created by Dima Bart on 2021-11-18.
//

import Foundation

struct Route {
    
    let path: Path
    let properties: [String: String]
    let fragments: [Fragment.Key: Fragment]
    
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }
        
        /// Handles route creation from multiple URL sources with different structures
        ///
        /// Routes can be created from two types of URLs:
        /// - **Universal Links**: `https://example.com/path` path is in the URL path component
        /// - **Deep Links**: `flipcash://path` path is in the URL host component
        ///
        /// Since the path location differs between URL schemes, this method normalizes
        /// the extraction logic to support both formats.
        guard let path = Path.parse(path: components.path.isEmpty ? (components.host ?? "") : components.path) else {
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

extension Route {
    enum Path {

        case login
        case cash
        case verifyEmail
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
            default:
                return .unknown(url.lastPathComponent)
            }
        }
    }
}

// MARK: - Fragment -

extension Route {
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

extension Route.Fragment {
    enum Key: String, CaseIterable {
        case entropy = "e"
        case payload = "p"
        case key     = "k" // (Unused)
        case data    = "d" // (Unused)
    }
}
