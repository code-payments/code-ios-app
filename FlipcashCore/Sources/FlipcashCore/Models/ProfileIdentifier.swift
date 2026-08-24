//
//  ProfileIdentifier.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// Whose profile to fetch. Mirrors the `GetProfileRequest.identifier` oneof: a
/// profile is looked up by exactly one of a user id or a username.
public enum ProfileIdentifier: Equatable, Sendable {
    case userID(UserID)
    case username(Username)
}

extension ProfileIdentifier: CustomStringConvertible {

    /// Kind-tagged, so a log line says which arm of the oneof was used. Both
    /// arms are public identifiers, so neither is redacted.
    public var description: String {
        switch self {
        case .userID(let userID):     "userId:\(userID)"
        case .username(let username): "username:\(username)"
        }
    }
}

// MARK: - Proto -

extension ProfileIdentifier {

    var proto: Flipcash_Profile_V1_GetProfileRequest.OneOf_Identifier {
        switch self {
        case .userID(let userID):     .userID(.with { $0.value = userID.data })
        case .username(let username): .username(.with { $0.value = username.value })
        }
    }
}
