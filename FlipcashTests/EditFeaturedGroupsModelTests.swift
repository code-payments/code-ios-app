//
//  EditFeaturedGroupsModelTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("EditFeaturedGroupsModel")
struct EditFeaturedGroupsModelTests {

    private struct Boom: Error {}

    @MainActor
    private final class Calls {
        var submitted: [[ConversationID]] = []
        var handedBack: [[Conversation]] = []
    }

    private func group(_ byte: UInt8, title: String? = nil, isPrivate: Bool = false, type: ConversationType = .group) -> Conversation {
        Conversation(
            id: ConversationID(data: Data(repeating: byte, count: 32)),
            members: [],
            lastMessage: nil,
            lastActivity: Date(timeIntervalSince1970: 0),
            type: type,
            title: title,
            isPrivate: isPrivate
        )
    }

    private func makeModel(
        cached: [Conversation] = [],
        featured: [Conversation]? = [],
        joined: [Conversation] = [],
        calls: Calls = Calls(),
        saving: (([ConversationID]) async throws -> [Conversation])? = nil
    ) -> EditFeaturedGroupsModel {
        EditFeaturedGroupsModel(
            featured: cached,
            loadingFeatured: { featured },
            joinedGroups: { joined },
            saving: { ids in
                calls.submitted.append(ids)
                return try await saving?(ids) ?? []
            },
            saved: { calls.handedBack.append($0) }
        )
    }

    @Test("Candidates are the featured groups in their order, then joined public groups")
    func candidatesOrder() async {
        let a = group(1), b = group(2), c = group(3), secret = group(4, isPrivate: true), dm = group(5, type: .tipDm)
        let model = makeModel(featured: [b, a], joined: [a, c, secret, dm])

        await model.loadCandidates()

        #expect(model.candidates.map(\.id) == [b.id, a.id, c.id])
        #expect(model.selection == [b.id, a.id])
        #expect(model.loadState == .loaded)
    }

    @Test("A featured group the user has left stays on offer so it can be removed")
    func leftGroupStays() async {
        let left = group(1)
        let model = makeModel(featured: [left], joined: [])

        await model.loadCandidates()

        #expect(model.candidates.map(\.id) == [left.id])
        #expect(model.isSelected(left.id))
    }

    @Test("Toggling appends at the end of the order and removes in place")
    func toggleOrder() async {
        let a = group(1), b = group(2), c = group(3)
        let model = makeModel(featured: [a], joined: [b, c])
        await model.loadCandidates()

        model.toggle(c.id)
        model.toggle(b.id)
        #expect(model.selection == [a.id, c.id, b.id])

        model.toggle(a.id)
        #expect(model.selection == [c.id, b.id])
    }

    @Test("No more than ten can be chosen, and a chosen one can still be dropped")
    func capsAtLimit() async {
        let groups = (1...11).map { group(UInt8($0)) }
        let model = makeModel(featured: [], joined: groups)
        await model.loadCandidates()

        groups.prefix(FeaturedGroups.limit).forEach { model.toggle($0.id) }
        #expect(model.selection.count == FeaturedGroups.limit)
        #expect(!model.canToggle(groups[10].id))

        model.toggle(groups[10].id)
        #expect(model.selection.count == FeaturedGroups.limit)

        #expect(model.canToggle(groups[0].id))
        model.toggle(groups[0].id)
        #expect(model.selection.count == FeaturedGroups.limit - 1)
    }

    @Test("Save stays shut until the featured list is read, and while unchanged")
    func canSave() async {
        let a = group(1), b = group(2)
        let model = makeModel(cached: [a], featured: [a], joined: [b])

        model.toggle(a.id)
        #expect(!model.canSave)

        await model.loadCandidates()
        // A choice made while loading stands.
        #expect(model.selection.isEmpty)
        #expect(model.canSave)

        model.toggle(a.id)
        #expect(!model.canSave)
    }

    @Test("A failed read of the featured list keeps Save shut")
    func failedLoad() async {
        let a = group(1)
        let model = makeModel(cached: [], featured: nil, joined: [a])

        await model.loadCandidates()
        model.toggle(a.id)

        #expect(model.loadState == .failed)
        #expect(!model.canSave)
    }

    @Test("An untouched selection follows the re-read list")
    func untouchedSelectionFollowsServer() async {
        let stale = group(1), fresh = group(2)
        let model = makeModel(cached: [stale], featured: [fresh])

        await model.loadCandidates()

        #expect(model.selection == [fresh.id])
        #expect(!model.canSave)
    }

    @Test("Saving submits the ordered selection and hands back the server's list")
    func saveSubmits() async {
        let a = group(1), b = group(2)
        let calls = Calls()
        let model = makeModel(featured: [a], joined: [b], calls: calls) { _ in [b, a] }
        await model.loadCandidates()
        model.toggle(a.id)
        model.toggle(b.id)
        model.toggle(a.id)

        await model.save()

        #expect(calls.submitted == [[b.id, a.id]])
        #expect(calls.handedBack.map { $0.map(\.id) } == [[b.id, a.id]])
        #expect(model.state == .saved)
    }

    @Test("Clearing every group saves an empty list")
    func saveEmpty() async {
        let a = group(1)
        let calls = Calls()
        let model = makeModel(featured: [a], calls: calls)
        await model.loadCandidates()
        model.toggle(a.id)

        await model.save()

        #expect(calls.submitted == [[]])
    }

    @Test("A denied save names the private-group failure and leaves the selection")
    func deniedSave() async {
        let a = group(1)
        let model = makeModel(featured: [], joined: [a]) { _ in throw ErrorSetFeaturedGroups.denied }
        await model.loadCandidates()
        model.toggle(a.id)

        await model.save()

        #expect(model.failure == .privateGroup)
        #expect(model.state == .normal)
        #expect(model.selection == [a.id])
    }

    @Test("Any other failure is generic")
    func otherFailure() async {
        let a = group(1)
        let model = makeModel(featured: [], joined: [a]) { _ in throw Boom() }
        await model.loadCandidates()
        model.toggle(a.id)

        await model.save()

        #expect(model.failure == .other)
        #expect(model.state == .normal)
    }

    @Test("Search filters by title, ignoring case")
    func search() async {
        let cats = group(1, title: "Cat People"), dogs = group(2, title: "Dog people")
        let model = makeModel(featured: [], joined: [cats, dogs])
        await model.loadCandidates()

        model.query = "cat"
        #expect(model.visibleCandidates.map(\.id) == [cats.id])

        model.query = "  "
        #expect(model.visibleCandidates.count == 2)
    }
}
