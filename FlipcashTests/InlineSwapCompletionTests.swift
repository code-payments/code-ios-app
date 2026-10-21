//
//  InlineSwapCompletionTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import UserNotifications
@testable import FlipcashCore
@testable import Flipcash

private final class PollRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(attempts: Int, interval: Duration)] = []
    var calls: [(attempts: Int, interval: Duration)] { lock.withLock { _calls } }
    func record(_ attempts: Int, _ interval: Duration) { lock.withLock { _calls.append((attempts, interval)) } }
}

@Suite("InlineSwapCompletion")
@MainActor
struct InlineSwapCompletionTests {

    private func completion(
        recorder: PollRecorder = PollRecorder(),
        result: @escaping () throws -> SwapMetadata
    ) -> InlineSwapCompletion {
        InlineSwapCompletion(
            reporter: SwapCompletionReporter(swapId: .generate(), swapType: .buyWithReserves, targetMint: .jeffy, amount: .mockOne),
            poll: { attempts, interval in
                recorder.record(attempts, interval)
                return try result()
            }
        )
    }

    @Test("Window is 250ms polls for 5s")
    func windowConstants() {
        #expect(InlineCompletion.pollInterval == .milliseconds(250))
        #expect(InlineCompletion.window == .seconds(5))
        #expect(InlineCompletion.maxAttempts == 20)
        #expect(InlineCompletion.slowPathCredit == 5)
        #expect(InlineCompletion.successHold == .seconds(1))
    }

    @Test("A finalized swap succeeds and polls at the fast interval")
    func finalizedSucceeds() async {
        let recorder = PollRecorder()
        let outcome = await completion(recorder: recorder) { .makeTest(state: .finalized) }.awaitOutcome()
        #expect(outcome == .succeeded)
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first?.attempts == 20)
        #expect(recorder.calls.first?.interval == .milliseconds(250))
    }

    @Test("Failed and cancelled swaps fail inline", arguments: [SwapState.failed, .cancelled])
    func terminalFailure(_ state: SwapState) async {
        let outcome = await completion { .makeTest(state: state) }.awaitOutcome()
        #expect(outcome == .failed)
    }

    @Test("An intermediate state at the cap falls back to the processing screen", arguments: [SwapState.funding, .submitting, .unknown])
    func intermediateIsPending(_ state: SwapState) async {
        let outcome = await completion { .makeTest(state: state) }.awaitOutcome()
        #expect(outcome == .pending)
    }

    @Test("Poll limit and cancellation are never inline failures")
    func timeoutAndCancellationArePending() async {
        #expect(await completion { throw ClientError.pollLimitReached }.awaitOutcome() == .pending)
        #expect(await completion { throw CancellationError() }.awaitOutcome() == .pending)
    }

    @Test("An RPC error fails inline")
    func rpcErrorFails() async {
        struct Boom: Error {}
        #expect(await completion { throw Boom() }.awaitOutcome() == .failed)
    }

    // MARK: - Convert view model

    private func convertContext(
        poll: @escaping () throws -> SwapMetadata
    ) throws -> (ConvertConfirmationViewModel, SessionContainer, AppRouter, DismissCounter) {
        let container = try SessionContainer.makeTest(holdings: [])
        let vm = ConvertConfirmationViewModelTests.fromDollars()
        vm.swapPoller = { _ in { _, _ in try poll() } }
        vm.successHold = .zero
        vm.dismissDelay = .zero
        vm.notificationPrompt = NotificationPrompt(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            status: { .denied },
            authorize: {}
        )
        let router = AppRouter()
        router.present(.give)
        return (vm, container, router, DismissCounter())
    }

    final class DismissCounter { var count = 0 }

    @Test("Convert: fast success skips processing and dismisses once")
    func convertFastSuccess() async throws {
        let (vm, container, router, dismissed) = try convertContext { .makeTest(state: .finalized) }
        await vm.completeInline(swapId: .generate(), session: container.session, router: router) { dismissed.count += 1 }
        #expect(dismissed.count == 1)
        #expect(vm.actionButtonState == .success)
        #expect(router[.give].isEmpty)
    }

    @Test("Convert: pending falls back to the processing screen")
    func convertPendingPushesProcessing() async throws {
        let (vm, container, router, dismissed) = try convertContext { .makeTest(state: .funding) }
        await vm.completeInline(swapId: .generate(), session: container.session, router: router) { dismissed.count += 1 }
        #expect(dismissed.count == 0)
        #expect(vm.actionButtonState == .normal)
        #expect(router[.give].count == 1)
    }

    @Test("Convert: terminal failure stays, resets the button, and shows an error")
    func convertFailureStays() async throws {
        let (vm, container, router, dismissed) = try convertContext { .makeTest(state: .failed) }
        await vm.completeInline(swapId: .generate(), session: container.session, router: router) { dismissed.count += 1 }
        #expect(dismissed.count == 0)
        #expect(vm.actionButtonState == .normal)
        #expect(vm.dialogItem != nil)
        #expect(router[.give].isEmpty)
    }

    // MARK: - Notification prompt

    @Test("The notification explainer shows once, only when undetermined")
    func notificationPromptShownOnce() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var presented = 0
        let prompt = NotificationPrompt(defaults: defaults, status: { .notDetermined }, authorize: {})
        await prompt.presentIfNeeded { _ in presented += 1 }
        await prompt.presentIfNeeded { _ in presented += 1 }
        #expect(presented == 1)
        #expect(prompt.hasShown)
    }

    @Test("The notification explainer is skipped once permission is decided", arguments: [UNAuthorizationStatus.denied, .authorized])
    func notificationPromptSkipped(_ status: UNAuthorizationStatus) async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var presented = 0
        let prompt = NotificationPrompt(defaults: defaults, status: { status }, authorize: {})
        await prompt.presentIfNeeded { _ in presented += 1 }
        #expect(presented == 0)
        #expect(!prompt.hasShown)
    }
}
