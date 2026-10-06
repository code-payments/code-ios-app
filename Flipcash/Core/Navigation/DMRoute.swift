//
//  DMRoute.swift
//  Flipcash
//

import FlipcashCore

/// Where opening a person lands: their DM once it exists, their profile until then.
nonisolated enum DMRoute {

    /// The destination for opening `userID`, given the DM with them if there is one.
    static func destination(
        for userID: UserID,
        dmID: ConversationID?,
        origin: UserProfileOrigin
    ) -> AppRouter.Destination {
        if let dmID {
            return .tipConversation(dmID)
        }
        return .userProfile(userID, origin: origin)
    }
}
