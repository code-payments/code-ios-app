//
//  EmailVerificationViewModelTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

/// Runs serialized — the skip-verification cases mutate
/// `CoinbaseOrderEmail.unverifiedEmail` (UserDefaults-backed), so parallel
/// execution within the suite would race on the shared key.
@MainActor
@Suite("EmailVerificationViewModel", .serialized)
struct EmailVerificationViewModelTests {

    @Test("applyDeeplinkVerification parks the user on confirmEmail and stashes the email")
    func applyDeeplinkVerification_setsConfirmEmailPath() {
        let viewModel = EmailVerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))
        #expect(viewModel.verificationPath == [.confirmEmailCode])
        #expect(viewModel.enteredEmail == "a@b.c")
    }

    // MARK: - Skip-verification mode -

    @Test("Flag off: send stores the email locally and finishes without the confirm screen")
    func sendEmailCode_skipMode_storesLocallyAndFinishes() async throws {
        let prior = CoinbaseOrderEmail.unverifiedEmail
        defer { CoinbaseOrderEmail.unverifiedEmail = prior }
        CoinbaseOrderEmail.unverifiedEmail = nil

        let session = Session.unverifiedMock
        session.userFlags = .fixture(requireCoinbaseEmailVerification: false)
        let viewModel = EmailVerificationViewModel(session: session, flipClient: .mock)
        viewModel.enteredEmail = "user@example.com"

        var finished = false
        viewModel.onVerified = { finished = true }

        viewModel.sendEmailCodeAction()
        try await waitUntil(viewModel) { _ in finished }

        #expect(CoinbaseOrderEmail.unverifiedEmail == "user@example.com")
        #expect(viewModel.verificationPath.isEmpty, "skip mode must not push the confirm screen")
    }

    @Test("isAlreadyVerified: a stored local email satisfies the requirement")
    func isAlreadyVerified_localEmailSatisfies() {
        let prior = CoinbaseOrderEmail.unverifiedEmail
        defer { CoinbaseOrderEmail.unverifiedEmail = prior }
        CoinbaseOrderEmail.unverifiedEmail = "user@example.com"

        let session = Session.unverifiedMock
        session.userFlags = .fixture(requireCoinbaseEmailVerification: false)
        let viewModel = EmailVerificationViewModel(session: session, flipClient: .mock)

        #expect(viewModel.isAlreadyVerified)
    }
    // MARK: - Verified means server-verified -

    @Test("isAlreadyVerified, verification required: an email linked without a code does not count")
    func isAlreadyVerified_required_unverifiedLinkedEmail_isFalse() {
        let prior = CoinbaseOrderEmail.unverifiedEmail
        defer { CoinbaseOrderEmail.unverifiedEmail = prior }
        CoinbaseOrderEmail.unverifiedEmail = nil

        let session = Session.unverifiedMock
        session.userFlags = .fixture(requireCoinbaseEmailVerification: true)
        session.profile = Profile(displayName: "Test", phone: .mock, email: "linked@example.com", isEmailAddressVerified: false)
        let viewModel = EmailVerificationViewModel(session: session, flipClient: .mock)

        #expect(!viewModel.isAlreadyVerified)
    }

    @Test("isAlreadyVerified, verification required: a server-verified email counts")
    func isAlreadyVerified_required_verifiedEmail_isTrue() {
        let session = Session.verifiedMock
        session.userFlags = .fixture(requireCoinbaseEmailVerification: true)
        let viewModel = EmailVerificationViewModel(session: session, flipClient: .mock)

        #expect(viewModel.isAlreadyVerified)
    }

    @Test("isAlreadyVerified, verification not required: an email linked without a code counts")
    func isAlreadyVerified_notRequired_unverifiedLinkedEmail_isTrue() {
        let prior = CoinbaseOrderEmail.unverifiedEmail
        defer { CoinbaseOrderEmail.unverifiedEmail = prior }
        CoinbaseOrderEmail.unverifiedEmail = nil

        let session = Session.unverifiedMock
        session.userFlags = .fixture(requireCoinbaseEmailVerification: false)
        session.profile = Profile(displayName: "Test", phone: .mock, email: "linked@example.com", isEmailAddressVerified: false)
        let viewModel = EmailVerificationViewModel(session: session, flipClient: .mock)

        #expect(viewModel.isAlreadyVerified)
    }
}
