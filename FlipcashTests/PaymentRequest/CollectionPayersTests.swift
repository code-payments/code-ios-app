//
//  CollectionPayersTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// A collection's paid list merges live payer updates past the version its page was read at, and the
/// viewer counts as paid only once a read of the request has answered.
@MainActor
@Suite("Group payment requests: a collection's payers")
struct CollectionPayersTests {

    private let id = PaymentRequestID(data: Data([1]))
    private let viewer = UUID()
    private let jordan = UUID()
    private let sam = UUID()

    private func paid(_ userID: UserID, at seconds: TimeInterval = 0) -> GroupPaymentRequest.Payer {
        .init(userID: userID, nativeAmountDue: 0, nativeAmountPaid: 10, status: .paid(paidAt: Date(timeIntervalSince1970: seconds), settlement: .intent(Data([7]))))
    }

    @Test("A page keeps only paid payers, in the order read")
    func pageKeepsPaid() {
        let payers = CollectionPayers()
        let unpaid = GroupPaymentRequest.Payer(userID: sam, nativeAmountDue: 10, nativeAmountPaid: 0, status: .unpaid)

        payers.record(page: [paid(jordan, at: 2), unpaid, paid(viewer, at: 1)], version: 3, for: id)

        #expect(payers.paidPayers(of: id)?.map(\.userID) == [jordan, viewer])
    }

    @Test("A live payer past the page's version goes first; one at or below it is dropped")
    func liveUpdateGatedOnPageVersion() {
        let payers = CollectionPayers()
        payers.record(page: [paid(jordan)], version: 5, for: id)

        payers.apply([paid(sam)], version: 5, to: id)
        #expect(payers.paidPayers(of: id)?.map(\.userID) == [jordan])

        payers.apply([paid(sam)], version: 6, to: id)
        #expect(payers.paidPayers(of: id)?.map(\.userID) == [sam, jordan])
    }

    @Test("A live payer replaces the held one by user id")
    func liveUpdateReplacesByUserID() {
        let payers = CollectionPayers()
        payers.record(page: [paid(sam), paid(jordan)], version: 1, for: id)

        payers.apply([paid(jordan, at: 9)], version: 2, to: id)

        #expect(payers.paidPayers(of: id)?.map(\.userID) == [jordan, sam])
    }

    @Test("A live payer with no page held is dropped")
    func liveUpdateWithoutPage() {
        let payers = CollectionPayers()

        payers.apply([paid(sam)], version: 9, to: id)

        #expect(payers.paidPayers(of: id) == nil)
    }

    @Test("A page read before a newer live update doesn't undo it")
    func stalePageDropped() {
        let payers = CollectionPayers()
        payers.record(page: [], version: 1, for: id)
        payers.apply([paid(sam)], version: 4, to: id)

        payers.record(page: [], version: 3, for: id)

        #expect(payers.paidPayers(of: id)?.map(\.userID) == [sam])
    }

    @Test("Paid is unknown until a read of the request answers")
    func paidUnknownUntilRead() {
        let payers = CollectionPayers()
        payers.record(page: [paid(viewer)], version: 1, for: id)

        #expect(payers.hasPaid(id, viewer: viewer) == nil)
    }

    @Test("The viewer counts as paid from the read's caller payer or from the paid list")
    func paidFromCallerOrList() {
        let fromCaller = CollectionPayers()
        fromCaller.record(caller: paid(viewer), for: id)
        #expect(fromCaller.hasPaid(id, viewer: viewer) == true)

        let fromList = CollectionPayers()
        fromList.record(caller: nil, for: id)
        #expect(fromList.hasPaid(id, viewer: viewer) == false)
        fromList.record(page: [], version: 1, for: id)
        fromList.apply([paid(viewer)], version: 2, to: id)
        #expect(fromList.hasPaid(id, viewer: viewer) == true)
    }
}
