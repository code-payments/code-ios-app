//
//  PhoneVerificationPath.swift
//  Flipcash
//

/// Navigation path for a standalone phone verification flow's NavigationStack.
/// `EnterPhoneScreen` is the stack root; this enum only carries the pushed
/// destinations.
enum PhoneVerificationPath: Hashable {
    case confirmPhoneNumberCode
}
