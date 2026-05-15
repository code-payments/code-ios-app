//
//  VerificationOperationTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@Suite("VerificationOperation") @MainActor
struct VerificationOperationTests {

    @Test("Fully-verified profile completes immediately without calling FlipClient")
    func fullyVerified_returnsImmediately() async throws {
        let session = MockSession(profile: .fullyVerified)
        let client = MockContactVerifying()
        let op = VerificationOperation(session: session, flipClient: client)

        try await op.start()

        #expect(op.state == .idle)
        #expect(client.sendVerificationCodeCalls.isEmpty)
        #expect(client.sendEmailVerificationCalls.isEmpty)
    }

    @Test("Phone-only unverified: phone flow runs end-to-end, email skipped")
    func phoneOnlyUnverified_phoneFlowRunsEndToEnd() async throws {
        let session = MockSession(profile: .needsPhoneOnly)
        let client = MockContactVerifying()
        let op = VerificationOperation(session: session, flipClient: client)

        async let result: Void = op.start()

        try await waitUntil(op) { $0.state == .awaitingPhone }
        let phone = Phone.mock
        op.submitPhone(phone)

        try await waitUntil(op) { $0.state == .awaitingPhoneCode }

        // Wire updateProfile to flip phone-verified after the check call lands.
        session.updateProfileHandler = {
            session.profile = .fullyVerified
        }
        op.submitPhoneCode("123456")

        try await result
        #expect(op.state == .idle)
        #expect(client.sendVerificationCodeCalls.map(\.phone) == [phone.e164])
        #expect(client.checkVerificationCodeCalls.map(\.code) == ["123456"])
        #expect(client.sendEmailVerificationCalls.isEmpty)
    }

    @Test("Both unverified: phone runs first, then email")
    func bothUnverified_phoneThenEmail() async throws {
        let session = MockSession(profile: .needsBoth)
        let client = MockContactVerifying()
        let op = VerificationOperation(session: session, flipClient: client)

        async let result: Void = op.start()

        try await waitUntil(op) { $0.state == .awaitingPhone }
        op.submitPhone(Phone.mock)

        try await waitUntil(op) { $0.state == .awaitingPhoneCode }
        session.updateProfileHandler = {
            // Phone verified, email still missing.
            session.profile = Profile(displayName: nil, phone: .mock, email: Optional<String>.none)
        }
        op.submitPhoneCode("111111")

        try await waitUntil(op) { $0.state == .awaitingEmail }
        op.submitEmail("user@example.com")

        try await waitUntil(op) { $0.state == .awaitingEmailCode }
        session.updateProfileHandler = {
            session.profile = .fullyVerified
        }
        op.submitEmailCode("222222")

        try await result
        #expect(op.state == .idle)
        #expect(client.sendVerificationCodeCalls.count == 1)
        #expect(client.checkVerificationCodeCalls.count == 1)
        #expect(client.sendEmailVerificationCalls.map(\.email) == ["user@example.com"])
        #expect(client.checkEmailCodeCalls.map(\.code) == ["222222"])
    }

    @Test("Cancel while awaiting phone throws CancellationError")
    func cancel_whileAwaitingPhone_throws() async {
        let session = MockSession(profile: .needsBoth)
        let client = MockContactVerifying()
        let op = VerificationOperation(session: session, flipClient: client)

        let task = Task { try await op.start() }
        try? await waitUntil(op) { $0.state == .awaitingPhone }
        op.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Server error during checkVerificationCode propagates")
    func checkVerificationCode_serverError_propagates() async throws {
        let session = MockSession(profile: .needsPhoneOnly)
        let client = MockContactVerifying()
        client.checkVerificationCodeHandler = { _, _, _ in
            throw MockError.serverRejected
        }
        let op = VerificationOperation(session: session, flipClient: client)

        let task = Task { try await op.start() }
        try await waitUntil(op) { $0.state == .awaitingPhone }
        op.submitPhone(Phone.mock)

        try await waitUntil(op) { $0.state == .awaitingPhoneCode }
        op.submitPhoneCode("000000")

        await #expect(throws: MockError.serverRejected) {
            try await task.value
        }
    }
}

// MARK: - Mocks

@MainActor
private final class MockContactVerifying: ContactVerifying {

    private(set) var sendVerificationCodeCalls: [(phone: String, owner: KeyPair)] = []
    private(set) var checkVerificationCodeCalls: [(phone: String, code: String, owner: KeyPair)] = []
    private(set) var sendEmailVerificationCalls: [(email: String, owner: KeyPair)] = []
    private(set) var checkEmailCodeCalls: [(email: String, code: String, owner: KeyPair)] = []

    var sendVerificationCodeHandler: (@MainActor (String, KeyPair) async throws -> Void)?
    var checkVerificationCodeHandler: (@MainActor (String, String, KeyPair) async throws -> Void)?
    var sendEmailVerificationHandler: (@MainActor (String, KeyPair) async throws -> Void)?
    var checkEmailCodeHandler: (@MainActor (String, String, KeyPair) async throws -> Void)?

    func sendVerificationCode(phone: String, owner: KeyPair) async throws {
        sendVerificationCodeCalls.append((phone, owner))
        try await sendVerificationCodeHandler?(phone, owner)
    }

    func checkVerificationCode(phone: String, code: String, owner: KeyPair) async throws {
        checkVerificationCodeCalls.append((phone, code, owner))
        try await checkVerificationCodeHandler?(phone, code, owner)
    }

    func sendEmailVerification(email: String, owner: KeyPair) async throws {
        sendEmailVerificationCalls.append((email, owner))
        try await sendEmailVerificationHandler?(email, owner)
    }

    func checkEmailCode(email: String, code: String, owner: KeyPair) async throws {
        checkEmailCodeCalls.append((email, code, owner))
        try await checkEmailCodeHandler?(email, code, owner)
    }
}

private enum MockError: Error, Equatable {
    case serverRejected
}

private extension Profile {
    static var fullyVerified: Profile {
        Profile(displayName: nil, phone: .mock, email: "user@example.com")
    }
    static var needsPhoneOnly: Profile {
        Profile(displayName: nil, phone: Optional<Phone>.none, email: "user@example.com")
    }
    static var needsBoth: Profile {
        Profile(displayName: nil, phone: Optional<Phone>.none, email: nil)
    }
}
