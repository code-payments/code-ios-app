//
//  EditBioModelTests.swift
//  FlipcashTests
//

import Testing
import FlipcashAPI
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("EditBioModel")
struct EditBioModelTests {

    private struct Boom: Error {}

    @MainActor
    private final class Calls {
        var saved: [String] = []
        var refreshCount = 0
        var order: [String] = []
    }

    private func makeModel(
        bio: String = "Hello",
        calls: Calls = Calls(),
        saving: ((String) async throws -> Void)? = nil
    ) -> EditBioModel {
        EditBioModel(
            bio: bio,
            saving: { text in
                calls.order.append("save")
                calls.saved.append(text)
                try await saving?(text)
            },
            refresh: {
                calls.order.append("refresh")
                calls.refreshCount += 1
            }
        )
    }

    @Test("The text starts as the current bio and the counter counts down from 160")
    func initialState() {
        let model = makeModel(bio: "Hello")

        #expect(model.text == "Hello")
        #expect(model.remaining == 155)
    }

    @Test("Save is shut while unchanged or over the limit, open when cleared")
    func canSave() {
        let model = makeModel(bio: "Hello")
        #expect(!model.canSave)

        model.text = "Hello there"
        #expect(model.canSave)

        model.text = String(repeating: "a", count: 161)
        #expect(model.remaining == -1)
        #expect(!model.canSave)

        model.text = String(repeating: "a", count: 160)
        #expect(model.canSave)

        model.text = ""
        #expect(model.canSave)
    }

    @Test("A successful save sends the trimmed text, then refreshes, then reports saved")
    func saveSucceeds() async {
        let calls = Calls()
        let model = makeModel(calls: calls)
        model.text = "  New bio \n"

        await model.save()

        #expect(calls.saved == ["New bio"])
        #expect(calls.order == ["save", "refresh"])
        #expect(model.state == .saved)
        #expect(model.fieldError == nil)
        #expect(model.failure == nil)
    }

    @Test("Moderation shows an inline error and keeps the text")
    func moderated() async {
        let calls = Calls()
        let model = makeModel(calls: calls) { _ in throw ErrorProfile.moderated(.init()) }
        model.text = "flagged"

        await model.save()

        #expect(model.state == .normal)
        #expect(model.fieldError == .moderated)
        #expect(model.text == "flagged")
        #expect(model.failure == nil)
        #expect(calls.refreshCount == 0)
    }

    @Test("An invalid bio shows an inline error and keeps the text")
    func invalid() async {
        let model = makeModel { _ in throw ErrorProfile.invalidBio }
        model.text = "bad"

        await model.save()

        #expect(model.state == .normal)
        #expect(model.fieldError == .invalid)
        #expect(model.text == "bad")
    }

    @Test("Any other error has no field to blame and raises a failure")
    func otherError() async {
        let model = makeModel { _ in throw Boom() }
        model.text = "something"

        await model.save()

        #expect(model.state == .normal)
        #expect(model.fieldError == nil)
        #expect(model.failure != nil)
    }

    @Test("Editing the text clears the inline error")
    func editingClearsFieldError() async {
        let model = makeModel { _ in throw ErrorProfile.invalidBio }
        model.text = "bad"
        await model.save()
        #expect(model.fieldError == .invalid)

        model.text = "better"

        #expect(model.fieldError == nil)
    }
}
