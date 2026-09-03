//
//  MessagePolicy.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// How a deleted message occupies its place in the transcript.
public enum DeletedMessagePresentation: Hashable, Sendable, Codable {
    /// A muted bubble reading "You deleted this message" / "This message was deleted". Keeps the
    /// sender's side, the timestamp, and the grouping, so a reply quoting it still has a target.
    case placeholder
    /// The row is dropped entirely — the transcript's behaviour before deletion existed.
    case hidden
}

/// The tunables that govern what may be done to a message and how a deleted one is shown. Group
/// chats will eventually vary these per conversation; today every conversation gets the windows
/// the server sends on ``UserFlags``, or ``MessagePolicy/default`` before those have arrived.
public struct MessagePolicy: Hashable, Sendable {

    /// How long after sending a message stays editable, or `nil` for no limit.
    ///
    /// The server sends this on ``UserFlags``; when it sends nothing we fall back to
    /// ``fallbackEditWindow`` rather than leaving the action open forever. That is a deliberate
    /// reversal: the previous rule defaulted to `nil` on the grounds that a client-side window
    /// would only hide an action the server would have accepted. It can now do exactly that — a
    /// message past the fallback loses Edit even where the server would have taken the request.
    /// We accept that because an affordance the server *will* reject is the worse failure, and
    /// because the fallback matches Android's, so the two clients offer the same rows for the
    /// same message.
    public let editWindow: TimeInterval?

    /// How long after sending a message stays deletable, or `nil` for no limit. Same source and
    /// same trade-off as ``editWindow``, falling back to ``fallbackDeleteWindow``.
    public let deleteWindow: TimeInterval?

    public let deletedPresentation: DeletedMessagePresentation

    /// The window applied when the server sends no edit window. Kept in step with Android's
    /// constant of the same value so both clients gate identically.
    public static let fallbackEditWindow: TimeInterval = 900       // 15 minutes

    /// The window applied when the server sends no delete window. Kept in step with Android's
    /// constant of the same value so both clients gate identically.
    public static let fallbackDeleteWindow: TimeInterval = 172_800 // 48 hours

    public init(
        editWindow: TimeInterval?,
        deleteWindow: TimeInterval?,
        deletedPresentation: DeletedMessagePresentation
    ) {
        self.editWindow = editWindow
        self.deleteWindow = deleteWindow
        self.deletedPresentation = deletedPresentation
    }

    /// Builds the policy in force from the server's feature flags, substituting the fallback
    /// windows for anything the server left unset.
    ///
    /// `userFlags` is optional because ``Session/userFlags`` is: it is `nil` until the cached row
    /// is restored, and a failed fetch never assigns, so it stays at whatever it was — `nil` with
    /// no cached row, otherwise flags whose own window fields may be unset. Optional-chaining
    /// collapses all three of those into the same expression, so this one fallback is also the
    /// failed-fetch behaviour and there is no second path to keep in step. `nil` on the model keeps
    /// meaning "the server said nothing"; the substitution happens only here.
    public init(userFlags: UserFlags?, deletedPresentation: DeletedMessagePresentation = .placeholder) {
        self.init(
            editWindow: userFlags?.messageEditWindow ?? Self.fallbackEditWindow,
            deleteWindow: userFlags?.messageDeleteWindow ?? Self.fallbackDeleteWindow,
            deletedPresentation: deletedPresentation
        )
    }

    /// The window governing `capability`, or `nil` when it never lapses.
    public func window(for capability: MessageCapability) -> TimeInterval? {
        switch capability {
        case .edit:         editWindow
        case .delete:       deleteWindow
        case .copy, .reply: nil
        }
    }

    /// The policy in force before any flags have been read — the fallback windows.
    public static let `default` = MessagePolicy(userFlags: nil)
}
