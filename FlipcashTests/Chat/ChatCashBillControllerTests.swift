//
//  ChatCashBillControllerTests.swift
//  FlipcashTests
//

import Testing
import Foundation
import FlipcashCore
@testable import Flipcash

@MainActor
private final class FakeKeyboard: ChatComposerKeyboard {
    var isUp: Bool
    private(set) var lowered = 0
    private(set) var raised = 0
    init(isUp: Bool) { self.isUp = isUp }
    func lower() { lowered += 1; isUp = false }
    func raise() { raised += 1; isUp = true }
}

@Suite("ChatCashBillController")
@MainActor
struct ChatCashBillControllerTests {

    private let me = UUID()
    private let them = UUID()
    private let chat = ConversationID(data: Data(repeating: 0xA1, count: 32))
    private let otherChat = ConversationID(data: Data(repeating: 0xB2, count: 32))

    /// A controller wired to fakes. `shown` collects the bills it presents; closing one is the test's call.
    private final class Probe {
        var shown: [Session.BillDescription] = []
        var onTop = false
        var foreground = true
        var billShowing = false
        var open: ConversationID?
        var verified: VerifiedState? = .fresh()
        var gate: CheckedContinuation<Void, Never>?
    }

    private func make(keyboardUp: Bool, probe: Probe) -> (ChatCashBillController, FakeKeyboard) {
        let controller = ChatCashBillController(selfUserID: me)
        let keyboard = FakeKeyboard(isUp: keyboardUp)
        controller.keyboard = keyboard
        controller.isEnabled = { true }
        controller.openConversationID = { probe.open }
        controller.somethingOnTop = { probe.onTop }
        controller.isForeground = { probe.foreground }
        controller.isBillShowing = { probe.billShowing }
        controller.verifiedState = { _ in
            await withCheckedContinuation { probe.gate = $0 }
            return probe.verified
        }
        controller.present = { description in
            probe.shown.append(description)
            probe.billShowing = true
        }
        return (controller, keyboard)
    }

    private func cash(id: UInt64 = 10) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: them,
            content: .cash(ExchangedFiat(nativeAmount: .usd(20), rate: .oneToOne)),
            cashAction: .sent, cashReceiverID: me,
            date: Date(timeIntervalSince1970: 2_000_000), unreadSeq: 1
        )
    }

    /// Lets the controller's task reach its verified-state await, then releases it.
    private func settle(_ probe: Probe) async {
        for _ in 0..<50 where probe.gate == nil { await Task.yield() }
        probe.gate?.resume()
        probe.gate = nil
        for _ in 0..<20 { await Task.yield() }
    }

    private func closeBill(_ probe: Probe, _ controller: ChatCashBillController) {
        probe.billShowing = false
        controller.billDidClose()
    }

    // 1, 16 (toast half)
    @Test("A live payment presents a received bill of my amount with no deposit toast")
    func presentsReceivedBillWithoutToast() async throws {
        let probe = Probe(); probe.open = chat
        let (controller, _) = make(keyboardUp: false, probe: probe)

        controller.handleLive([cash()], in: chat, countedThrough: MessageID(value: 1))
        await settle(probe)

        let bill = try #require(probe.shown.first)
        #expect(bill.received)
        #expect(!bill.announcesDeposit)
        #expect(bill.exchangedFiat.nativeAmount.value == 20)
        #expect(bill.verifiedState != nil)
    }

    // 12
    @Test("Keyboard up: lowered for the bill, raised when it closes")
    func keyboardRestoredOnClose() async {
        let probe = Probe(); probe.open = chat
        let (controller, keyboard) = make(keyboardUp: true, probe: probe)

        controller.handleLive([cash()], in: chat, countedThrough: nil)
        await settle(probe)
        #expect(keyboard.lowered == 1)
        #expect(!keyboard.isUp)

        closeBill(probe, controller)
        #expect(keyboard.raised == 1)
        #expect(keyboard.isUp)
    }

    // 13: swipe, scrim and back all end in the same close callback.
    @Test("Any close route restores the keyboard once, and a second close does not raise it again")
    func closeRestoresOnce() async {
        let probe = Probe(); probe.open = chat
        let (controller, keyboard) = make(keyboardUp: true, probe: probe)
        controller.handleLive([cash()], in: chat, countedThrough: nil)
        await settle(probe)

        closeBill(probe, controller)
        controller.billDidClose()

        #expect(keyboard.raised == 1)
    }

    // 14
    @Test("Keyboard down stays down")
    func keyboardDownStaysDown() async {
        let probe = Probe(); probe.open = chat
        let (controller, keyboard) = make(keyboardUp: false, probe: probe)
        controller.handleLive([cash()], in: chat, countedThrough: nil)
        await settle(probe)
        closeBill(probe, controller)

        #expect(keyboard.lowered == 0)
        #expect(keyboard.raised == 0)
    }

    // 15
    @Test("A bill closed by backgrounding does not raise the keyboard on return")
    func backgroundedDoesNotRestore() async {
        let probe = Probe(); probe.open = chat
        let (controller, keyboard) = make(keyboardUp: true, probe: probe)
        controller.handleLive([cash()], in: chat, countedThrough: nil)
        await settle(probe)

        probe.foreground = false
        closeBill(probe, controller)
        probe.foreground = true
        controller.billDidClose()

        #expect(keyboard.raised == 0)
    }

    // 10
    @Test("A second payment while the first is preparing or showing is dropped and not queued")
    func secondPaymentDropped() async {
        let probe = Probe(); probe.open = chat
        let (controller, _) = make(keyboardUp: false, probe: probe)

        controller.handleLive([cash(id: 10)], in: chat, countedThrough: nil)
        // Still waiting on verified state: the bill is not up yet.
        controller.handleLive([cash(id: 11)], in: chat, countedThrough: MessageID(value: 10))
        await settle(probe)
        // Showing.
        controller.handleLive([cash(id: 12)], in: chat, countedThrough: MessageID(value: 11))
        await settle(probe)
        #expect(probe.shown.count == 1)

        closeBill(probe, controller)
        await settle(probe)
        #expect(probe.shown.count == 1)
    }

    // 8, 9
    @Test("Something on top drops the payment before any bill is prepared")
    func onTopDrops() async {
        let probe = Probe(); probe.open = chat; probe.onTop = true
        let (controller, keyboard) = make(keyboardUp: true, probe: probe)

        controller.handleLive([cash()], in: chat, countedThrough: nil)
        await settle(probe)

        #expect(probe.shown.isEmpty)
        #expect(keyboard.lowered == 0)
    }

    @Test("A sheet that opens while verified state is awaited drops the bill and leaves the keyboard alone")
    func sheetOpensDuringPrepare() async {
        let probe = Probe(); probe.open = chat
        let (controller, keyboard) = make(keyboardUp: true, probe: probe)

        controller.handleLive([cash()], in: chat, countedThrough: nil)
        probe.onTop = true
        await settle(probe)

        #expect(probe.shown.isEmpty)
        #expect(keyboard.lowered == 0)
    }

    @Test("Without verified state no bill shows, since its give operation would fail")
    func noVerifiedStateNoBill() async {
        let probe = Probe(); probe.open = chat; probe.verified = nil
        let (controller, _) = make(keyboardUp: false, probe: probe)

        controller.handleLive([cash()], in: chat, countedThrough: nil)
        await settle(probe)

        #expect(probe.shown.isEmpty)
    }

    // 5, 6, 11
    @Test("Another chat, no chat open, or the flag off: nothing is prepared")
    func notQualifying() async {
        let probe = Probe(); probe.open = otherChat
        let (controller, _) = make(keyboardUp: false, probe: probe)
        controller.handleLive([cash()], in: chat, countedThrough: nil)
        #expect(probe.gate == nil)

        probe.open = nil
        controller.handleLive([cash()], in: chat, countedThrough: nil)
        #expect(probe.gate == nil)

        probe.open = chat
        controller.isEnabled = { false }
        controller.handleLive([cash()], in: chat, countedThrough: nil)
        #expect(probe.gate == nil)
        #expect(probe.shown.isEmpty)
    }

    // 19
    @Test("The message that raises the bill is the one the chat skips its haptic for")
    func hapticSkippedForBilledMessage() async {
        let probe = Probe(); probe.open = chat
        let (controller, _) = make(keyboardUp: false, probe: probe)

        controller.handleLive([cash(id: 10)], in: chat, countedThrough: nil)

        #expect(controller.isBilling(MessageID(value: 10)))
        #expect(!controller.isBilling(MessageID(value: 11)))
        await settle(probe)
    }

    @Test("A dropped payment keeps its haptic")
    func droppedPaymentKeepsHaptic() async {
        let probe = Probe(); probe.open = chat; probe.onTop = true
        let (controller, _) = make(keyboardUp: false, probe: probe)

        controller.handleLive([cash(id: 10)], in: chat, countedThrough: nil)

        #expect(!controller.isBilling(MessageID(value: 10)))
    }
}
