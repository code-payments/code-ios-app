//
//  TypingDotsHandoff.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The rule both platforms share for which arrival, if any, takes over the typing-dots row's frame
/// in an update that delivers messages. Android encodes the same rule and the same case table.
public enum TypingDotsHandoff {

    /// The index into `arrivals` (oldest first) of the message that takes over the dots row's
    /// frame, or nil when every arrival inserts above the dots with the normal push.
    ///
    /// Only the newest arrival can take it, and only when its sender was typing before the update
    /// (a typist lingering after STOPPED counts) and nobody is typing after it. Handing the dots to
    /// one sender while others still type would open a second dots row under the new message.
    public static func takerIndex<Participant: Hashable>(
        typingBefore: Set<Participant>,
        arrivals: [Participant],
        typingAfter: Set<Participant>
    ) -> Int? {
        guard typingAfter.isEmpty, let newest = arrivals.last, typingBefore.contains(newest) else { return nil }
        return arrivals.count - 1
    }
}
