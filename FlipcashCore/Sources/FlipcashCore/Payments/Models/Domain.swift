//
//  Domain.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import WebURL
import WebURLFoundationExtras

public struct Domain: Equatable, Codable, Hashable, Sendable {
    
    public let relationshipHost: String
    public let urlString: String
    
    public var displayTitle: String {
        let string = relationshipHost
        let firstCharacter = relationshipHost.prefix(1).capitalized
        return "\(firstCharacter)\(relationshipHost.suffix(string.count - 1))"
    }
    
    // MARK: - Init -
    
    public init?(_ url: URL, supportSubdomains: Bool = false) {
        self.init(url.absoluteString, supportSubdomains: supportSubdomains)
    }
    
    public init?(_ string: String, supportSubdomains: Bool = false) {
        guard var url = URL(string: string) else {
            return nil
        }
        
        url = url.scheme == nil ? URL(string: "https://\(string)")! : url
        
        guard
            let webURL = WebURL(url),
            let hostname = webURL.host?.serialized,
            let baseHost = Self.baseDomain(from: hostname, supportSubdomains: supportSubdomains)
        else {
            return nil
        }
        
        self.urlString = string
        self.relationshipHost = baseHost
    }
    
    // MARK: - Utilities -
    
    static func baseDomain(from hostname: String, supportSubdomains: Bool) -> String? {
        let separator = "."
        let components = hostname.components(separatedBy: separator)
        
        guard components.count > 1 else {
            return nil
        }
        
        //  1     2     3
        // app.getcode.com
        //
        //    1     2
        // getcode.com
        //
        let componentCount = supportSubdomains ? 3 : 2
        
        return components.suffix(componentCount).joined(separator: separator)
    }
}
