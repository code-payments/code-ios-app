//
//  ReplyReturnStackTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
@testable import FlipcashCore

@Suite("Reply return stack")
struct ReplyReturnStackTests {

    private func stack(_ origins: String...) -> ReplyReturnStack {
        var stack = ReplyReturnStack()
        for origin in origins { stack.push(origin: origin) }
        return stack
    }

    @Test("A new chat has nowhere to return to")
    func startsEmpty() {
        #expect(ReplyReturnStack().isEmpty)
    }

    @Test("Each quote tap pushes its origin, newest on top")
    func pushStacksOrigins() {
        #expect(stack("a", "b", "c").origins == ["a", "b", "c"])
    }

    @Test("A second tap in the top origin doesn't push it again")
    func pushSkipsTopDuplicate() {
        #expect(stack("a", "b", "b").origins == ["a", "b"])
    }

    @Test("An origin lower in the stack can be pushed again")
    func pushAllowsNonTopRepeat() {
        #expect(stack("a", "b", "a").origins == ["a", "b", "a"])
    }

    @Test("A pop returns the newest origin first, then the next")
    func popReturnsNewestFirst() {
        var stack = stack("a", "b")
        #expect(stack.popOrigin { _ in true } == "b")
        #expect(stack.popOrigin { _ in true } == "a")
        #expect(stack.popOrigin { _ in true } == nil)
        #expect(stack.isEmpty)
    }

    @Test("A pop discards origins no longer in the chat and lands on the next one")
    func popSkipsMissingOrigins() {
        var stack = stack("a", "b", "c")
        #expect(stack.popOrigin { $0 != "c" && $0 != "b" } == "a")
        #expect(stack.isEmpty)
    }

    @Test("A pop with every origin gone empties the stack")
    func popAllMissing() {
        var stack = stack("a", "b")
        #expect(stack.popOrigin { _ in false } == nil)
        #expect(stack.isEmpty)
    }

    @Test("Scrolling to the top origin drops it and every reached one under it")
    func dropReachedPopsReachedTops() {
        var stack = stack("a", "b", "c")
        stack.dropReached { $0 == "c" || $0 == "b" }
        #expect(stack.origins == ["a"])
    }

    @Test("An unreached top keeps every entry, even reached ones under it")
    func dropReachedStopsAtFirstUnreached() {
        var stack = stack("a", "b", "c")
        stack.dropReached { $0 == "a" || $0 == "b" }
        #expect(stack.origins == ["a", "b", "c"])
    }

    @Test("Clearing forgets every origin")
    func clearEmpties() {
        var stack = stack("a", "b")
        stack.clear()
        #expect(stack.isEmpty)
    }
}
