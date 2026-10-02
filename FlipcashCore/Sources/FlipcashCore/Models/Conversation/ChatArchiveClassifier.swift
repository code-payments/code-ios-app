//
//  ChatArchiveClassifier.swift
//  FlipcashCore
//

import Foundation

/// Decides whether a message is addressed to the viewer, for rule 3. Each answer is `unknown` when
/// the device cannot tell, and ``ChatArchiveRules`` treats `unknown` as `no`, so a missing handle,
/// an undecrypted body or an unstored reply target all stay silent.
public enum ChatArchiveClassifier {

    /// Whether `message` @mentions `viewerUsername`. Only a decrypted text body can be inspected;
    /// anything else is `unknown`. Links are excluded the way the transcript does, so a handle inside
    /// a URL is not a mention.
    public static func mentionsViewer(
        _ message: ConversationMessage?,
        viewerUsername: String?
    ) -> ChatArchiveSignal {
        guard let viewerUsername else { return .unknown }
        guard let message, case .text(let text) = message.content else { return .unknown }
        let links = LinkDetector().webLinks(in: text)
        let handles = MentionDetector.mentions(in: text, excluding: links).map(\.username.value)
        return handles.contains(viewerUsername.lowercased()) ? .yes : .no
    }

    /// Whether `message` replies to one of the viewer's messages. `authorOf` resolves the replied-to
    /// message's sender from whatever the caller can reach (the fetched preview, then the store); it
    /// returns `nil` when the target is not available.
    public static func repliesToViewer(
        _ message: ConversationMessage?,
        selfUserID: UserID,
        authorOf: (MessageID) -> UserID?
    ) -> ChatArchiveSignal {
        guard let message else { return .unknown }
        guard let target = message.repliedTo else { return .no }
        guard let author = authorOf(target) else { return .unknown }
        return author == selfUserID ? .yes : .no
    }
}
