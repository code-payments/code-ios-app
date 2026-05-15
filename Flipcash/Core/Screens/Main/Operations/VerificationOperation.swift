//
//  VerificationOperation.swift
//  Flipcash
//

import Foundation
import Observation
import FlipcashCore

/// Verifies the user's phone and email with the Flipcash backend. Standalone
/// — not Coinbase-specific. `CoinbaseFundingOperation` consumes it via its
/// `.verifiedContact` requirement, but any future operation that gates on
/// verified contact info can reuse the same surface.
///
/// Linear flow: each "pause for user input" is a `CheckedContinuation` that
/// `submitPhone` / `submitPhoneCode` / `submitEmail` / `submitEmailCode`
/// resume. `state` is just a published view of where `run()` currently is.
@Observable
final class VerificationOperation {

    nonisolated enum State: Equatable, Sendable {
        case idle
        case awaitingPhone
        case awaitingPhoneCode
        case awaitingEmail
        case awaitingEmailCode
        case working
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let session: any (AccountProviding & ProfileProviding & ProfileManaging)
    @ObservationIgnored private let flipClient: any ContactVerifying

    @ObservationIgnored private var runTask: Task<Void, Error>?
    @ObservationIgnored private var phoneContinuation: CheckedContinuation<Phone, Error>?
    @ObservationIgnored private var phoneCodeContinuation: CheckedContinuation<String, Error>?
    @ObservationIgnored private var emailContinuation: CheckedContinuation<String, Error>?
    @ObservationIgnored private var emailCodeContinuation: CheckedContinuation<String, Error>?

    init(
        session: any (AccountProviding & ProfileProviding & ProfileManaging),
        flipClient: any ContactVerifying
    ) {
        self.session = session
        self.flipClient = flipClient
    }

    isolated deinit {
        runTask?.cancel()
    }

    // MARK: - Lifecycle

    func start() async throws {
        let task = Task { try await run() }
        runTask = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { [weak self] in
            task.cancel()
            // `onCancel` may run off the main actor; hop back to clean up
            // any awaiting continuations safely.
            Task { @MainActor [weak self] in
                self?.resumePendingContinuations(throwing: CancellationError())
            }
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    // MARK: - User submissions

    func submitPhone(_ phone: Phone) {
        phoneContinuation?.resume(returning: phone)
        phoneContinuation = nil
    }

    func submitPhoneCode(_ code: String) {
        phoneCodeContinuation?.resume(returning: code)
        phoneCodeContinuation = nil
    }

    func submitEmail(_ email: String) {
        emailContinuation?.resume(returning: email)
        emailContinuation = nil
    }

    func submitEmailCode(_ code: String) {
        emailCodeContinuation?.resume(returning: code)
        emailCodeContinuation = nil
    }

    // MARK: - Run

    private func run() async throws {
        if !isPhoneVerified {
            try await verifyPhone()
        }
        if !isEmailVerified {
            try await verifyEmail()
        }
        state = .idle
    }

    private func verifyPhone() async throws {
        state = .awaitingPhone
        let phone = try await waitForPhone()

        state = .working
        try await flipClient.sendVerificationCode(phone: phone.e164, owner: session.ownerKeyPair)

        state = .awaitingPhoneCode
        let code = try await waitForPhoneCode()

        state = .working
        try await flipClient.checkVerificationCode(phone: phone.e164, code: code, owner: session.ownerKeyPair)
        try await session.updateProfile()
    }

    private func verifyEmail() async throws {
        state = .awaitingEmail
        let email = try await waitForEmail()

        state = .working
        try await flipClient.sendEmailVerification(email: email, owner: session.ownerKeyPair)

        state = .awaitingEmailCode
        let code = try await waitForEmailCode()

        state = .working
        try await flipClient.checkEmailCode(email: email, code: code, owner: session.ownerKeyPair)
        try await session.updateProfile()
    }

    // MARK: - Profile helpers

    private var isPhoneVerified: Bool {
        session.profile?.isPhoneVerified ?? false
    }

    private var isEmailVerified: Bool {
        session.profile?.isEmailVerified ?? false
    }

    // MARK: - Continuations

    private func waitForPhone() async throws -> Phone {
        try await withCheckedThrowingContinuation { phoneContinuation = $0 }
    }
    private func waitForPhoneCode() async throws -> String {
        try await withCheckedThrowingContinuation { phoneCodeContinuation = $0 }
    }
    private func waitForEmail() async throws -> String {
        try await withCheckedThrowingContinuation { emailContinuation = $0 }
    }
    private func waitForEmailCode() async throws -> String {
        try await withCheckedThrowingContinuation { emailCodeContinuation = $0 }
    }

    private func resumePendingContinuations(throwing error: Error) {
        phoneContinuation?.resume(throwing: error); phoneContinuation = nil
        phoneCodeContinuation?.resume(throwing: error); phoneCodeContinuation = nil
        emailContinuation?.resume(throwing: error); emailContinuation = nil
        emailCodeContinuation?.resume(throwing: error); emailCodeContinuation = nil
    }
}
