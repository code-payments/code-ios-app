//
//  Database+Profile.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import SQLite

nonisolated extension Database {

    // MARK: - Get -

    func getProfile() throws -> Profile? {
        try getSingleton(Profile.self, in: ProfileTable())
    }

    func getUserFlags() throws -> UserFlags? {
        try getSingleton(UserFlags.self, in: UserFlagsTable())
    }

    // MARK: - Insert -

    func insertProfile(_ profile: Profile) throws {
        try upsertSingleton(profile, in: ProfileTable())
    }

    func insertUserFlags(_ userFlags: UserFlags) throws {
        try upsertSingleton(userFlags, in: UserFlagsTable())
    }
}
