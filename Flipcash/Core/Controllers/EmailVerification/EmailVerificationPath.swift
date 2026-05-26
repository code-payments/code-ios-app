//
//  EmailVerificationPath.swift
//  Flipcash
//

/// Navigation path for a standalone email verification flow's NavigationStack.
/// `EnterEmailScreen` is the stack root; this enum only carries the pushed
/// destination.
enum EmailVerificationPath: Hashable {
    case confirmEmailCode
}
