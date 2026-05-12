//
//  OnrampDeeplinkInbox.swift
//  Flipcash
//

import SwiftUI

/// Long-lived store for Onramp email verification deeplinks. `DeepLinkController`
/// drops incoming verifications here; `OnrampHostModifier` observes the value
/// with `.onChange(initial: true)` and hands it off to `OnrampCoordinator`, so
/// whether the link arrived before or after the sheet opened the verification
/// is picked up through the same entry point. Lives on `SessionContainer` so
/// it survives sheet dismissal but not logout.
@Observable
final class OnrampDeeplinkInbox {
    var pendingEmailVerification: VerificationDescription?
}
