//
//  Database+Profile.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    public func getProfile() throws -> Profile? {
        try getSingleton(Profile.self, in: ProfileTable())
    }

    public func getUserFlags() throws -> UserFlags? {
        try getSingleton(UserFlags.self, in: UserFlagsTable())
    }

    // MARK: - Insert -

    public func insertProfile(_ profile: Profile) throws {
        try upsertSingleton(profile, in: ProfileTable())
    }

    public func insertUserFlags(_ userFlags: UserFlags) throws {
        try upsertSingleton(userFlags, in: UserFlagsTable())
    }
}
