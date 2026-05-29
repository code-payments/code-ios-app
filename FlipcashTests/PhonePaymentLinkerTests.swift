//
//  PhonePaymentLinkerTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("PhonePaymentLinker")
struct PhonePaymentLinkerTests {

    private final class Recorder {
        var linked: [String] = []
    }

    @Test("Links once when enabled with a phone; a second call is a no-op")
    func linksOnceThenGuards() async {
        let recorder = Recorder()
        let linker = PhonePaymentLinker { recorder.linked.append($0) }

        await linker.linkExistingPhoneIfNeeded(phone: .mock, isSendEnabled: true)
        await linker.linkExistingPhoneIfNeeded(phone: .mock, isSendEnabled: true)

        #expect(recorder.linked == [Phone.mock.e164])
    }

    @Test("No-op when the send feature is disabled")
    func noOpWhenDisabled() async {
        let recorder = Recorder()
        let linker = PhonePaymentLinker { recorder.linked.append($0) }

        await linker.linkExistingPhoneIfNeeded(phone: .mock, isSendEnabled: false)

        #expect(recorder.linked.isEmpty)
    }

    @Test("No-op when there is no phone")
    func noOpWhenNoPhone() async {
        let recorder = Recorder()
        let linker = PhonePaymentLinker { recorder.linked.append($0) }

        await linker.linkExistingPhoneIfNeeded(phone: nil, isSendEnabled: true)

        #expect(recorder.linked.isEmpty)
    }
}
