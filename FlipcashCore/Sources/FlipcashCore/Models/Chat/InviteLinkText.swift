//
//  InviteLinkText.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Spots group invite links in message text, and keeps them out of the one-line previews built from it.
///
/// An invite link's fragment is the group's key, so a preview — the chat list's last line, a reply's
/// quote, a notification, Spotlight, a search hit — shows "Invite link" in its place. The link is
/// recognised the way the in-chat card recognises it: a web link `LinkDetector` finds, unwrapped
/// from `jump.flipcash.com`, on a Flipcash host, at `/chat/invite`. Whether the secret parses does
/// not matter; a broken one is hidden all the same.
public enum InviteLinkText {

    /// What a preview shows in place of each invite link.
    public static let placeholder = "Invite link"

    /// The hosts both apps claim. `Route.flipcashHosts` is this set, so a link is an invite link here
    /// exactly when the card treats it as one.
    public static let flipcashHosts: Set<String> = [
        "app.flipcash.com",
        "send.flipcash.com",
        "flipcash.com",
        "www.flipcash.com",
        "jump.flipcash.com",
    ]

    /// The real URL behind a `jump.flipcash.com` redirector, or nil if this is not one.
    ///
    /// A jump link carries its target percent-encoded in `#source=`. A jump pointing at another
    /// jump is malformed and is not followed. Mirrors Android `DeepLink.unwrapJumpTarget`.
    public static func unwrappingJump(_ url: URL) -> URL? {
        let prefix = "https://jump.flipcash.com/#source="
        guard url.absoluteString.hasPrefix(prefix) else { return nil }
        let encoded = String(url.absoluteString.dropFirst(prefix.count))
        guard let decoded = encoded.removingPercentEncoding,
              let target = URL(string: decoded),
              !decoded.hasPrefix(prefix)
        else { return nil }
        return target
    }

    /// Whether `url` is a group invite link, with or without a usable secret.
    public static func isInviteLink(_ url: URL) -> Bool {
        let target = unwrappingJump(url) ?? url
        guard let host = target.host()?.lowercased(), flipcashHosts.contains(host) else { return false }
        let path = target.pathComponents.filter { $0 != "/" }
        return path.count == 2 && path[0] == "chat" && path[1].lowercased() == "invite"
    }

    /// `text` with every invite link replaced by ``placeholder``; everything else is left as it is.
    public static func redacting(_ text: String, detector: LinkDetector = LinkDetector()) -> String {
        let invites = detector.webLinks(in: text).filter { isInviteLink($0.url) }
        guard !invites.isEmpty else { return text }
        let result = NSMutableString(string: text)
        for link in invites.reversed() {
            result.replaceCharacters(in: link.range, with: placeholder)
        }
        return result as String
    }
}
