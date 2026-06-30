//
//  Typing.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// A typing state the signed-in user broadcasts. The server infers the sender from auth, so only
/// the state crosses the wire. `timedOut` is server→client only and never sent.
public enum TypingState: Sendable, Equatable {
    case started
    case still
    case stopped

    var proto: Flipcash_Messaging_V1_IsTypingNotification.State {
        switch self {
        case .started: .startedTyping
        case .still: .stillTyping
        case .stopped: .stoppedTyping
        }
    }
}

/// A decoded typing notification for one member: `isActive` collapses the wire state to add-or-remove
/// (started/still → add the typist, stopped/timed-out → remove). Unknown states decode to `nil`.
public struct TypingNotification: Sendable, Hashable {
    public let userID: UserID
    public let isActive: Bool

    public init(userID: UserID, isActive: Bool) {
        self.userID = userID
        self.isActive = isActive
    }

    init?(_ proto: Flipcash_Messaging_V1_IsTypingNotification) {
        guard let userID = try? UUID(data: proto.userID.value) else { return nil }
        switch proto.state {
        case .startedTyping, .stillTyping:
            self.init(userID: userID, isActive: true)
        case .stoppedTyping, .typingTimedOut:
            self.init(userID: userID, isActive: false)
        case .unknownTypingState, .UNRECOGNIZED:
            return nil
        }
    }
}
