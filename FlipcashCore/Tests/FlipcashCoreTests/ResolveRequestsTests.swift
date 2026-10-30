//
//  ResolveRequestsTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import Synchronization
@testable import FlipcashCore

@Suite("ResolveRequests")
struct ResolveRequestsTests {

    @Test("A request reaches every stream")
    func fansOut() async {
        let requests = ResolveRequests()
        var first = requests.stream().makeAsyncIterator()
        var second = requests.stream().makeAsyncIterator()

        requests.request()

        #expect(await first.next() != nil)
        #expect(await second.next() != nil)
    }

    @Test("Requests inside the minimum interval are dropped, and the next one after it is sent")
    func dropsBurstWithinInterval() {
        let start = ContinuousClock.now
        let now = Mutex(start)
        let requests = ResolveRequests(minimumInterval: .seconds(5), now: { now.withLock { $0 } })

        #expect(requests.request())
        now.withLock { $0 = start + .seconds(1) }
        #expect(!requests.request())
        #expect(!requests.request())
        now.withLock { $0 = start + .seconds(5) }
        #expect(requests.request())
    }
}
