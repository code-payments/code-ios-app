//
//  PhonePaymentLinker.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Links an already-verified phone for payment once per session, so a phone
/// that predates the send feature becomes a payment target without
/// re-verifying. Best-effort and idempotent server-side; the once-guard resets
/// when the session (and this service) is recreated on logout.
@MainActor
final class PhonePaymentLinker {

    typealias LinkAction = @MainActor (_ phoneE164: String) async throws -> Void

    private let performLink: LinkAction
    private var hasLinked = false

    init(performLink: @escaping LinkAction) {
        self.performLink = performLink
    }

    /// Links `phone` for payment once. No-op when the send feature is disabled,
    /// no phone is present, or a link has already fired this session.
    func linkExistingPhoneIfNeeded(phone: Phone?, isSendEnabled: Bool) async {
        guard isSendEnabled, let phone, !hasLinked else { return }
        hasLinked = true
        do {
            try await performLink(phone.e164)
        } catch is CancellationError {
            return
        } catch {
            ErrorReporting.captureError(error)
        }
    }
}
