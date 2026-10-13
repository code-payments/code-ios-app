//
//  TrustedWebsitesTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@MainActor
@Suite struct TrustedWebsitesTests {

    private let defaults = UserDefaults(suiteName: "trusted-websites-\(UUID())")!

    private func store(at seconds: TimeInterval = 0) -> TrustedWebsites {
        TrustedWebsites(defaults: defaults, now: { Date(timeIntervalSince1970: seconds) })
    }

    @Test func startsEmpty() {
        #expect(store().entries.isEmpty)
    }

    @Test func trustAddsTheHostWithItsDate() {
        let sut = store(at: 100)
        sut.trust("x.com")
        #expect(sut.entries == [.init(host: "x.com", addedAt: Date(timeIntervalSince1970: 100))])
    }

    @Test func newestFirst() {
        store(at: 1).trust("youtube.com")
        store(at: 2).trust("x.com")
        #expect(store().entries.map(\.host) == ["x.com", "youtube.com"])
    }

    @Test func trustingTwiceKeepsTheFirstDate() {
        store(at: 1).trust("x.com")
        let sut = store(at: 2)
        sut.trust("x.com")
        #expect(sut.entries == [.init(host: "x.com", addedAt: Date(timeIntervalSince1970: 1))])
    }

    @Test func removeDropsOnlyThatHost() {
        let sut = store()
        sut.trust("x.com")
        sut.trust("mail.x.com")
        sut.remove("x.com")
        #expect(sut.hosts == ["mail.x.com"])
        #expect(store().hosts == ["mail.x.com"])
    }

    @Test func removingTheLastHostEmptiesTheList() {
        let sut = store()
        sut.trust("x.com")
        sut.remove("x.com")
        #expect(sut.entries.isEmpty)
        #expect(store().entries.isEmpty)
    }

    /// Logout and Switch Accounts clear named keys only, never this one, and the store lives on
    /// `Container`, which outlives the session. A fresh store on the same defaults stands in for
    /// the next account reading the list.
    @Test func survivesASimulatedLogout() {
        store().trust("x.com")
        #expect(store().hosts == ["x.com"])
    }
}
