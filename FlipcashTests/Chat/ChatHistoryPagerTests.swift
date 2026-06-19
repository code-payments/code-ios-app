//
//  ChatHistoryPagerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import FlipcashUI

@MainActor
@Suite("ChatHistoryPager")
struct ChatHistoryPagerTests {

    private func history(_ count: Int) -> [ChatMessage] {
        (0..<count).map { ChatMessage(id: "m\($0)", text: "message \($0)", sender: .me) }
    }

    private func pager(full: [ChatMessage], windowSize: Int, pageSize: Int) -> ChatHistoryPager {
        ChatHistoryPager(
            initial: Array(full.suffix(windowSize)),
            source: StaticOlderMessageSource(
                olderHistory: Array(full.prefix(full.count - windowSize)),
                pageSize: pageSize
            )
        )
    }

    @Test("Paging older eventually reaches the first message, in order")
    func paging_reachesFirstMessage() async {
        let full = history(100)
        let pager = pager(full: full, windowSize: 20, pageSize: 15)

        while pager.hasMoreOlder {
            #expect(await pager.loadOlderPage())
        }

        #expect(pager.messages == full)
        #expect(pager.messages.first?.id == "m0")
        #expect(!pager.hasMoreOlder)
    }

    @Test("Each load advances by exactly one page — never stuck")
    func paging_advancesOnePagePerCall() async {
        let full = history(50)
        let pager = pager(full: full, windowSize: 10, pageSize: 10)

        await pager.loadOlderPage()
        #expect(pager.messages.count == 20)
        await pager.loadOlderPage()
        #expect(pager.messages.count == 30)
        await pager.loadOlderPage()
        #expect(pager.messages.count == 40)
    }

    @Test("Loading past the end is a safe no-op")
    func paging_pastEnd_isNoOp() async {
        let full = history(12)
        let pager = pager(full: full, windowSize: 2, pageSize: 10)

        #expect(await pager.loadOlderPage())   // merges the remaining 10
        #expect(!pager.hasMoreOlder)
        #expect(!(await pager.loadOlderPage())) // exhausted → no-op, no crash
        #expect(pager.messages == full)
    }

    @Test("onChange delivers the merged transcript")
    func onChange_deliversMergedTranscript() async {
        let full = history(30)
        let pager = pager(full: full, windowSize: 10, pageSize: 20)
        var delivered: [ChatMessage]?
        pager.onChange = { delivered = $0 }

        await pager.loadOlderPage()

        #expect(delivered == full)
    }
}
