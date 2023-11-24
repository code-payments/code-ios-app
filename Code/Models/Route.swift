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
        
        guard let path = Path(path: components.path) else {
            return nil
        }
        
        // 1. Parse any query items into properties
        
        var properties: [String: String] = [:]
        
        components.queryItems?.forEach { queryItem in
            properties[queryItem.name] = queryItem.value ?? ""
        }
        
        // 2. Parse any fragment values into properties
        
        var fragments: [Fragment.Key: Fragment] = [:]
        
        if let urlFragment = components.fragment {
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
        case sdk
        case unknown(String)
        
        init?(path: String) {
            guard let url = URL(string: path) else {
                return nil
            }
            
            switch url.lastPathComponent {
            case "login":
                self = .login
            case "cash", "c":
                self = .cash
            case "payment-request-modal-desktop", "payment-request-modal-mobile":
                self = .sdk
            default:
                self = .unknown(url.lastPathComponent)
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
            self.value = value
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
