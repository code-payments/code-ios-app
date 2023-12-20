//
//  Domain.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import WebURL
import WebURLFoundationExtras

public struct Domain: Equatable, Codable, Hashable {
    
    public let relationshipHost: String
    public let urlString: String
    
    // MARK: - Init -
    
    public init?(_ url: URL) {
        self.init(url.absoluteString)
    }
    
    public init?(_ string: String) {
        guard var url = URL(string: string) else {
            return nil
        }
        
        url = url.scheme == nil ? URL(string: "https://\(string)")! : url
        
        guard
            let webURL = WebURL(url),
            let hostname = webURL.host?.serialized,
            let baseHost = Self.baseDomain(from: hostname)
        else {
            return nil
        }
        
        self.urlString = string
        self.relationshipHost = baseHost
    }
    
    // MARK: - Utilities -
    
    static func baseDomain(from hostname: String) -> String? {
        let separator = "."
        let components = hostname.components(separatedBy: separator)
        
        guard components.count > 1 else {
            return nil
        }
        
        return components.suffix(2).joined(separator: separator)
    }
}
