//
//  TwitterAccessToken.swift
//  Code
//
//  Created by Dima Bart on 2025-02-25.
//

import Foundation

struct TwitterAccessToken: Equatable, Hashable, Codable {
    
    /// The current access token, valid until `expiresAt`
    var accessToken: String
    
    /// The refresh token, used to renew authentication once the `accessToken` has expired. Only available when `scope` includes `offlineAccess`
    var refreshToken: String
    
    /// Date when the `accessToken` expires
    var expiresAt: Date
    
    /// The scope of permissions for this access token
    var scope: Set<String>
    
    /// Is token expired
    var isExpired: Bool {
        expiresAt < .now
    }
    
    init(accessToken: String, refreshToken: String, expiresAt: Date, scope: Set<String>) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }
    
    init(accessToken: String, refreshToken: String, expiresIn: Int, scope: [String]) {
        self.init(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: Date.now.timeIntervalSince1970 + TimeInterval(expiresIn)),
            scope: Set(scope)
        )
    }
}
