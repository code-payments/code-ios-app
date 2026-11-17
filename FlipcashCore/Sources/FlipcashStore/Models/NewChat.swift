//
//  NewChat.swift
//  FlipcashStore
//

import Foundation
import FlipcashCore

/// The New Chat chooser behind the Chats list's `+` (node 12391:77285): where each row leads. The
/// community row is gated on the account holding a community currency, by the same
/// ``Swift/Array/communityCurrencies()`` the community form defaults from. The screen maps each
/// destination to the app's router, so the shared behavior tests check the choice without the app
/// target.
public enum NewChat {

    /// A row of the chooser.
    public enum Choice: Sendable {
        case findByUsername
        case privateGroup
        case communityGroup
    }

    /// A screen the chooser pushes.
    public enum Destination: Hashable, Sendable {
        case usernameLookup
        case newPrivateGroup
        case newPublicGroup
        case discoverCurrencies
    }

    /// What tapping a row does.
    public enum Outcome: Equatable, Sendable {
        case open(Destination)
        /// The "No Community Currencies" dialog. Its Explore pushes ``explore`` onto this stack
        /// rather than routing to the Wallet tab, so the user stays in Chats.
        case noCommunityCurrencies
    }

    /// Where the dialog's Explore leads.
    public static let explore: Destination = .discoverCurrencies

    /// What tapping `choice` does, given the account's `balances` as `Session.balances(for:)`
    /// gives them. Only the community row reads them.
    public static func choose(_ choice: Choice, balances: @autoclosure () -> [ExchangedBalance]) -> Outcome {
        switch choice {
        case .findByUsername:
            return .open(.usernameLookup)
        case .privateGroup:
            return .open(.newPrivateGroup)
        case .communityGroup:
            return balances().communityCurrencies().isEmpty ? .noCommunityCurrencies : .open(.newPublicGroup)
        }
    }
}
