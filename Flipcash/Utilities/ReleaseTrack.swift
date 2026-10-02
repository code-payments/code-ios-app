//
//  ReleaseTrack.swift
//  Flipcash
//

import StoreKit

/// The distribution channel shown after the commit in the version footer, named as Android names it.
nonisolated enum ReleaseTrack {

    /// The track for this build: `development` for a DEBUG build, `beta` on TestFlight, and
    /// `nil` on the App Store or when StoreKit can't say.
    ///
    /// TestFlight and the App Store run the same Release binary, so only StoreKit's
    /// `AppTransaction` environment tells them apart.
    static func current() async -> String? {
        #if DEBUG
        return name(isDebug: true, environment: nil)
        #else
        let environment = try? await AppTransaction.shared.payloadValue.environment
        return name(isDebug: false, environment: environment)
        #endif
    }

    /// Maps a build to its track name; `nil` means no track is shown.
    static func name(isDebug: Bool, environment: AppStore.Environment?) -> String? {
        if isDebug {
            return "development"
        }
        // AppStore.Environment is a struct, so this can't be an exhaustive switch.
        if environment == .sandbox {
            return "beta"
        }
        return nil
    }
}
