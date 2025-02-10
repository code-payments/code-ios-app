//
//  Route.swift
//  Code
//
//  Created by Dima Bart on 2021-11-18.
//

import Foundation
import FlipchatServices

struct Route {
    
    let path: Path
    let properties: [String: String]
    let fragments: [Fragment.Key: Fragment]
    
    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw Error.failedToParseComponents
        }
        
        guard let path = try Path.parse(path: components.path) else {
            throw Error.failedToParsePath
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
    
    init(userActivity: NSUserActivity) throws {
        guard
            userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
        else {
            throw Error.noOpActivity
        }
        
        try self.init(url: url)
    }
    
    func value(for key: Fragment.Key) -> String? {
        properties[key.rawValue]
    }
}

// MARK: - Path -

extension Route {
    enum Path {
        
        case login
        case room(RoomNumber)
        case user
        case unknown([String])
        
        static func parse(path: String) throws -> Path? {
            guard let url = URL(string: path.trimmingCharacters(in: .init(charactersIn: "/"))) else {
                return nil
            }
            
            let components = url.pathComponents
            
            switch components.first {
            case "login":
                return .login
                
            case "room", "r", "id", "number":
                guard components.count == 2 else {
                    throw Error.invalidRoomURL
                }
                
                guard let roomNumber = RoomNumber(components[1]) else {
                    throw Error.invalidRoomURL
                }
                
                return .room(roomNumber)
                
            case "user", "u":
                return .user
                
            default:
                return .unknown(components)
            }
        }
    }
}

extension Route {
    enum Error: Swift.Error {
        case noOpActivity
        case failedToParseComponents
        case failedToParsePath
        case invalidRoomURL
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
        case message = "m"
    }
}
