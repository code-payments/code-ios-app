//
//  ApproveNewMembersTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Approve new members")
struct ApproveNewMembersTests {

    private let defaults: UserDefaults
    private let owner = KeyPair.generate()!.publicKey
    private let moony = ConversationID(data: Data(repeating: 1, count: 16))
    private let owls = ConversationID(data: Data(repeating: 2, count: 16))

    init() {
        let suite = "approve-new-members-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("Off for every group until the host turns it on")
    func offByDefault() {
        let store = ApproveNewMembers(defaults: defaults, owner: owner)
        #expect(!store.isOn(for: moony))
    }

    @Test("Each group keeps its own position, across a relaunch")
    func perGroup() {
        let store = ApproveNewMembers(defaults: defaults, owner: owner)
        store.set(true, for: moony)

        let relaunched = ApproveNewMembers(defaults: defaults, owner: owner)
        #expect(relaunched.isOn(for: moony))
        #expect(!relaunched.isOn(for: owls))

        relaunched.set(false, for: moony)
        #expect(!ApproveNewMembers(defaults: defaults, owner: owner).isOn(for: moony))
    }

    @Test("Another account on the device doesn't see the position")
    func perOwner() {
        ApproveNewMembers(defaults: defaults, owner: owner).set(true, for: moony)
        let other = ApproveNewMembers(defaults: defaults, owner: KeyPair.generate()!.publicKey)
        #expect(!other.isOn(for: moony))
    }
}

/// The group card's events, for either link: an invite link carries the group's secret, so no
/// payload may hold a URL.
@MainActor
@Suite("Group card payloads", .serialized)
struct GroupCardPayloadTests {

    init() {
        Analytics.tokenSymbolResolver = nil
    }

    @Test("The card's events carry no link")
    func noURL() {
        let sent = Analytics.recordingSends {
            Analytics.groupCardShown(memberCount: 3)
            Analytics.groupInviteShared(method: .download)
            Analytics.groupInviteShared(method: .share)
            Analytics.groupInviteShared(method: .theCopy)
        }
        #expect(sent.count == 4)
        for event in sent {
            for value in event.properties.values {
                let text = "\(value)"
                #expect(!text.contains("flipcash.com"), "\(event.name) carries \(text)")
                #expect(!text.contains("#s="), "\(event.name) carries \(text)")
            }
        }
    }
}
