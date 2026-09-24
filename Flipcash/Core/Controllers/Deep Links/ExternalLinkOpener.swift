//
//  ExternalLinkOpener.swift
//  Flipcash
//

import UIKit
import FlipcashCore
import FlipcashUI

/// Whether a link can leave the app straight away or only after a warning naming its host.
///
/// A link in a chat message is written by a stranger, and a drainer site reached from one looks
/// like any other page once Safari has it. The warning puts the real
/// host in front of the user first. Android runs the same check with the same cases.
nonisolated enum ExternalLinkCheck: Equatable {

    /// Opens without a warning: our own scheme, an exact match on ``Route/flipcashHosts``, or a
    /// scheme with no host (`mailto:`, the Settings app), which names no website.
    case open

    /// Opens only once the user has seen `host` and chosen to go on.
    case warn(host: String)

    /// Checks `url` against the first-party hosts on an exact match, so `evilflipcash.com` and
    /// `flipcash.com.evil.tld` both warn.
    init(url: URL) {
        if url.scheme?.lowercased() == Route.Path.customScheme {
            self = .open
            return
        }
        guard let host = Self.displayHost(of: url) else {
            self = .open
            return
        }
        self = Route.flipcashHosts.contains(host) ? .open : .warn(host: host)
    }

    /// The host as the warning shows it: lowercased, and in its ASCII (punycode) form so a
    /// homograph such as a Cyrillic `а` in `flipcаsh.com` cannot pass for the real name.
    ///
    /// `host(percentEncoded: false)` is the one Foundation accessor that returns IDNA's ASCII form;
    /// the default `host()` returns the Unicode percent-encoded. The ASCII check is a backstop for
    /// a host Foundation hands back decoded.
    private static func displayHost(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else {
            return nil
        }
        guard host.allSatisfy(\.isASCII) else {
            return url.host(percentEncoded: true)?.lowercased()
        }
        return host
    }
}

/// Opens a link from a chat message's text, first warning when its host is not one of ours.
///
/// Links the app builds itself open directly; only text someone else wrote goes through here.
@MainActor
struct ExternalLinkOpener {

    /// Where the warning is drawn.
    let session: Session

    /// Opens `url` now if ``ExternalLinkCheck`` allows it, otherwise once the user picks Open Link.
    func open(_ url: URL) {
        switch ExternalLinkCheck(url: url) {
        case .open:
            UIApplication.shared.open(url)

        case .warn(let host):
            session.dialogItem = .leavingFlipcash(host: host) {
                UIApplication.shared.open(url)
            }
        }
    }
}

extension DialogItem {

    /// The warning in front of a link to `host`, matching Android's copy word for word.
    ///
    /// Cancel is the primary button. The body is not emphasised around the host as Android's is:
    /// the dialog sets its whole subtitle in bold already.
    static func leavingFlipcash(host: String, open: @escaping () -> Void) -> DialogItem {
        .alert(
            title: "You're leaving Flipcash",
            subtitle: "This link opens \(host). Flipcash will never ask for your Access Key on a website"
        ) {
            DialogAction.standard("Cancel") {}
            DialogAction.subtle("Open Link", action: open)
        }
    }
}
