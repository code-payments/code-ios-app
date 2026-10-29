//
//  InlineBalanceCompletionTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash
import FlipcashStore

@Suite("InlineBalanceCompletion — Phantom inline settlement")
@MainActor
struct InlineBalanceCompletionTests {

    typealias Settling = AddMoneyProcessingViewModelTests.FakeAddMoneySettling

    private static let tenDollars = ExchangedFiat(
        onChainAmount: TokenAmount(quarks: 10_000_000, mint: .usdf),
        nativeAmount: .usd(10),
        currencyRate: .oneToOne
    )

    private static func balance(_ dollars: Decimal) throws -> StoredBalance {
        try AddMoneyProcessingViewModelTests.usdfBalance(dollars: dollars)
    }

    private static func settling(risesAfter updates: Int, to dollars: Decimal = 10) throws -> Settling {
        let settling = Settling()
        settling.usdfBalance = try balance(0)
        settling.risenBalance = try balance(dollars)
        settling.risesAfterUpdates = updates
        return settling
    }

    /// The default window only bounds a failing wait: a rise ends it early, so it can be long enough
    /// to hold under the Thread Sanitizer. Tests that expect `.pending` pass a short one.
    private static func completion(_ settling: Settling, window: Duration = .seconds(30)) -> InlineBalanceCompletion {
        InlineBalanceCompletion(
            settlement: settling,
            target: AddMoneyBalanceTarget.target(baseline: .zero(in: .usd), amount: tenDollars),
            window: window,
            interval: .milliseconds(1)
        )
    }

    private static func viewModel(settling: Settling) throws -> (AddMoneyAmountViewModel, Session) {
        let container = try SessionContainer.makeTest(holdings: [])
        let viewModel = AddMoneyAmountViewModel(
            method: .phantom,
            session: container.session,
            ratesController: container.ratesController,
            settlement: settling
        )
        viewModel.inlineWindow = .milliseconds(200)
        viewModel.inlineInterval = .milliseconds(1)
        viewModel.successHold = .zero
        return (viewModel, container.session)
    }

    // MARK: - Outcome

    @Test("A balance that rises within the window succeeds")
    func risesWithinWindow() async throws {
        let settling = try Self.settling(risesAfter: 3)
        let outcome = await Self.completion(settling).awaitOutcome()
        #expect(outcome == .succeeded)
        #expect(settling.updateCount == 3)
    }

    @Test("A credit short of the 98% target stays pending")
    func shortfallStaysPending() async throws {
        let settling = try Self.settling(risesAfter: 1, to: 9.7)
        let outcome = await Self.completion(settling, window: .milliseconds(30)).awaitOutcome()
        #expect(outcome == .pending)
    }

    @Test("A credit of exactly 98% succeeds")
    func toleranceBoundary() async throws {
        let settling = try Self.settling(risesAfter: 1, to: 9.8)
        let outcome = await Self.completion(settling).awaitOutcome()
        #expect(outcome == .succeeded)
    }

    @Test("A balance that never rises is pending once the window closes")
    func timesOutPending() async throws {
        let settling = try Self.settling(risesAfter: .max)
        let outcome = await Self.completion(settling, window: .milliseconds(30)).awaitOutcome()
        #expect(outcome == .pending)
        #expect(settling.updateCount >= 1)
    }

    // MARK: - View model hand-off

    @Test("Inline success dismisses the flow and never pushes the processing screen")
    func inlineSuccessDismisses() async throws {
        let (viewModel, session) = try Self.viewModel(settling: try Self.settling(risesAfter: 2))
        var dismissed = false
        var pushed: AddMoneyProcessingInput?

        await viewModel.completeInline(
            amount: Self.tenDollars,
            baseline: .zero(in: .usd),
            depositRef: "sig",
            dismiss: { dismissed = true },
            onProceed: { pushed = $0 }
        )

        #expect(dismissed)
        #expect(pushed == nil)
        #expect(viewModel.actionButtonState == .success)
        #expect(session.transactionNotificationPrompt.pending)
    }

    @Test("Timing out inline pushes the processing screen with the inline window deducted")
    func timeoutFallsBackWithElapsed() async throws {
        let (viewModel, session) = try Self.viewModel(settling: try Self.settling(risesAfter: .max))
        var dismissed = false
        var pushed: AddMoneyProcessingInput?

        await viewModel.completeInline(
            amount: Self.tenDollars,
            baseline: .zero(in: .usd),
            depositRef: "sig",
            dismiss: { dismissed = true },
            onProceed: { pushed = $0 }
        )

        #expect(!dismissed)
        #expect(pushed?.method == .phantom)
        #expect(pushed?.depositRef == "sig")
        #expect(pushed?.elapsed == .milliseconds(200))
        #expect(!session.transactionNotificationPrompt.pending)
    }

    @Test("The processing screen's timeout shrinks by the inline time already spent")
    func processingTimeoutDeductsElapsed() async throws {
        let settling = try Self.settling(risesAfter: .max)
        let input = AddMoneyProcessingInput(
            amount: Self.tenDollars, method: .phantom, depositRef: nil, elapsed: .milliseconds(9_950)
        )
        let viewModel = AddMoneyProcessingViewModel(input: input, pollInterval: .milliseconds(1), timeout: .seconds(10))

        let started = ContinuousClock.now
        await viewModel.run(settlement: settling, performSweep: { true })

        #expect(viewModel.displayState == .failed)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    // MARK: - Card timing

    @Test("Card settlement polls faster and keeps the earlier wall-time budgets")
    func cardTiming() {
        #expect(AddMoneyTiming.sweepBackoff == .seconds(1))
        #expect(AddMoneyTiming.sweepMaxAttempts == 60)
        #expect(AddMoneyTiming.sweepBackoff * AddMoneyTiming.sweepMaxAttempts == .seconds(60))
        #expect(AddMoneyTiming.balancePollInterval == .milliseconds(500))
        #expect(AddMoneyTiming.settlementTimeout == .seconds(120))
    }
}
