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

    /// Opens without a warning: our own scheme, an exact match on ``Route/flipcashHosts`` or on a
    /// host the user trusted, or a scheme with no host (`mailto:`, the Settings app), which names
    /// no website.
    case open

    /// Opens only once the user has seen `host` and chosen to go on.
    case warn(host: String)

    /// Checks `url` against the first-party hosts and `trustedHosts` on an exact match, so
    /// `evilflipcash.com` and `flipcash.com.evil.tld` both warn, and trusting `x.com` does not
    /// cover `mail.x.com`.
    init(url: URL, trustedHosts: Set<String> = []) {
        if url.scheme?.lowercased() == Route.Path.customScheme {
            self = .open
            return
        }
        guard let host = Self.displayHost(of: url) else {
            self = .open
            return
        }
        if Route.flipcashHosts.contains(host) || trustedHosts.contains(host) {
            self = .open
        } else {
            self = .warn(host: host)
        }
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

    /// The hosts that skip the warning, and where Don't ask again saves one.
    let trustedWebsites: TrustedWebsites

    /// Opens `url` now if ``ExternalLinkCheck`` allows it, otherwise once the user picks Open Website.
    func open(_ url: URL) {
        switch ExternalLinkCheck(url: url, trustedHosts: trustedWebsites.hosts) {
        case .open:
            UIApplication.shared.open(url)

        case .warn(let host):
            session.dialogItem = .leavingFlipcash(host: host, trustedWebsites: trustedWebsites) {
                UIApplication.shared.open(url)
            }
        }
    }
}

extension DialogItem {

    /// The warning in front of a link to `host`, matching Android's copy word for word.
    ///
    /// Open Website is the primary button. Tapping it with Don't ask again ticked adds `host` to
    /// `trustedWebsites`; Cancel and dismissing save nothing. The body is not emphasised around
    /// the host as Android's is: the dialog sets its whole subtitle in bold already.
    static func leavingFlipcash(
        host: String,
        trustedWebsites: TrustedWebsites,
        open: @escaping () -> Void
    ) -> DialogItem {
        DialogItem.info(
            title: "You're Leaving Flipcash",
            subtitle: "This will open \(host). Never share your Access Key with a website"
        ) {
            DialogAction.standard("Open Website") { isChecked in
                if isChecked {
                    trustedWebsites.trust(host)
                }
                open()
            }
            DialogAction.cancel()
        }
        .checkbox("Don't ask again for \(host)")
    }
}
