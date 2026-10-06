//
//  EditGroupDescriptionModelTests.swift
//  FlipcashTests
//

import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Group description editor")
struct EditGroupDescriptionModelTests {

    private struct Boom: Error {}

    @MainActor
    private final class Calls {
        var edits: [ConversationDescriptionEdit] = []
    }

    private func makeModel(
        description: String = "Bad boys only",
        calls: Calls = Calls(),
        saving: ((ConversationDescriptionEdit) async throws -> Void)? = nil
    ) -> EditGroupDescriptionModel {
        EditGroupDescriptionModel(description: description) { edit in
            calls.edits.append(edit)
            try await saving?(edit)
        }
    }

    @Test("The text starts as the current description and the counter counts down from 160")
    func initialState() {
        let model = makeModel(description: "Hello")

        #expect(model.text == "Hello")
        #expect(model.remaining == 155)
    }

    @Test("Save is shut while unchanged or over the limit, open when cleared")
    func canSave() {
        let model = makeModel(description: "Hello")
        #expect(!model.canSave)

        model.text = "Hello there"
        #expect(model.canSave)

        model.text = String(repeating: "a", count: 161)
        #expect(!model.canSave)

        model.text = ""
        #expect(model.canSave)
    }

    @Test("A changed description is sent trimmed as a set, and the save lands")
    func savesTrimmedDescription() async {
        let calls = Calls()
        let model = makeModel(calls: calls)
        model.text = "  Good boys only \n"

        await model.save()

        #expect(calls.edits == [.set("Good boys only")])
        #expect(model.state == .saved)
        #expect(model.fieldError == nil)
        #expect(model.failure == nil)
    }

    @Test("An emptied description is sent as a clear, not as an empty set")
    func emptyDescriptionClears() async {
        let calls = Calls()
        let model = makeModel(calls: calls)
        model.text = "   "

        await model.save()

        #expect(calls.edits == [.clear])
        #expect(model.state == .saved)
    }

    @Test("A moderation rejection lands under the field and reopens Save")
    func moderationRejectionShowsInline() async {
        let model = makeModel { _ in throw ErrorEditChat.descriptionModerated(.init()) }
        model.text = "Something else"

        await model.save()

        #expect(model.fieldError == .moderated)
        #expect(model.failure == nil)
        #expect(model.state == .normal)
        #expect(model.canSave)
    }

    @Test("Editing the text clears a moderation error")
    func editingClearsFieldError() async {
        let model = makeModel { _ in throw ErrorEditChat.descriptionModerated(.init()) }
        model.text = "Something else"
        await model.save()

        model.text = "Something kinder"

        #expect(model.fieldError == nil)
    }

    @Test("Any other failure surfaces as a dialog, not under the field")
    func otherFailureSurfacesAsDialog() async {
        let model = makeModel { _ in throw Boom() }
        model.text = "Something else"

        await model.save()

        #expect(model.failure is Boom)
        #expect(model.fieldError == nil)
        #expect(model.state == .normal)
    }
}
