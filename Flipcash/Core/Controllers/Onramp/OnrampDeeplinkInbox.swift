//
//  OnrampDeeplinkInbox.swift
//  Flipcash
//

import SwiftUI

/// Long-lived store for Onramp email verification deeplinks. `DeepLinkController`
/// drops incoming verifications here; `OnrampHostModifier` observes the value
/// with `.onChange(initial: true)` and forwards it to `VerificationCoordinator`,
/// so whether the link arrived before or after a verification flow opened the
/// coordinator picks it up through the same entry point. Lives on
/// `SessionContainer` so it survives sheet dismissal but not logout.
@Observable
@MainActor
final class OnrampDeeplinkInbox {
    var pendingEmailVerification: VerificationDescription?
}
