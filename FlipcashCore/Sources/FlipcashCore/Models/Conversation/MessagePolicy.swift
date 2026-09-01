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
/// chats will eventually vary these per conversation; today every conversation gets `.default`.
public struct MessagePolicy: Hashable, Sendable {

    /// How long after sending a message stays editable, or `nil` for no limit. The server does not
    /// enforce a window today, so the default is `nil` — a client-side window would only hide an
    /// action the server would have accepted.
    public let editWindow: TimeInterval?
    public let deletedPresentation: DeletedMessagePresentation

    public init(editWindow: TimeInterval?, deletedPresentation: DeletedMessagePresentation) {
        self.editWindow = editWindow
        self.deletedPresentation = deletedPresentation
    }

    public static let `default` = MessagePolicy(editWindow: nil, deletedPresentation: .placeholder)
}
