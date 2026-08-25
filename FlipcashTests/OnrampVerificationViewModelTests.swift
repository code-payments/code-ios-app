//
//  OnrampVerificationViewModelTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("OnrampVerificationViewModel")
struct OnrampVerificationViewModelTests {

    @Test("applyDeeplinkVerification forwards to the inner email VM and resets Onramp's path")
    func applyDeeplinkVerification_forwardsAndSetsPath() {
        let viewModel = OnrampVerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))
        #expect(viewModel.verificationPath == [.confirmEmailCode])
        #expect(viewModel.emailVerifier.enteredEmail == "a@b.c")
    }

    // MARK: - Pushed hosting -

    /// Stands in for the host `NavigationStack` a pushed flow lives on.
    @MainActor
    private final class HostStack {
        var steps: [OnrampVerificationPath]
        init(steps: [OnrampVerificationPath]) { self.steps = steps }
    }

    /// Builds a flow pushed onto `stack` with `.intro` as its root.
    private func makePushedFlow(on stack: HostStack) -> OnrampVerification {
        let viewModel = OnrampVerificationViewModel(session: .unverifiedMock, flipClient: .mock)
        viewModel.pushedHost = PushedVerificationHost(
            rootStep: .intro,
            push: { stack.steps.append($0) },
            liveStepCount: { stack.steps.count }
        )
        return viewModel
    }

    /// A pushed flow suspended in `run()`, ready to be advanced or backed out of.
    private func makeRunningPushedFlow(on stack: HostStack) async -> (OnrampVerification, Task<Void, Error>) {
        let viewModel = makePushedFlow(on: stack)
        let run = Task { try await viewModel.run() }
        while viewModel.continuation == nil { await Task.yield() }
        return (viewModel, run)
    }

    @Test("The root step being covered by the next step leaves the flow running")
    func pushedFlow_rootStepCovered_keepsRunning() async {
        let stack = HostStack(steps: [.intro])
        let (viewModel, run) = await makeRunningPushedFlow(on: stack)

        viewModel.proceedFromIntro()
        #expect(stack.steps == [.intro, .enterPhoneNumber])

        // SwiftUI disappears the intro when phone entry covers it. The flow
        // must survive that, or the pushed step renders with no view model.
        viewModel.cancelIfBackedOut(from: .intro)
        #expect(viewModel.continuation != nil)

        viewModel.cancel()
        _ = await run.result
    }

    @Test("Popping the root step off the host stack cancels the flow")
    func pushedFlow_rootStepPopped_cancels() async throws {
        let stack = HostStack(steps: [.intro])
        let (viewModel, run) = await makeRunningPushedFlow(on: stack)

        stack.steps.removeAll()
        viewModel.cancelIfBackedOut(from: .intro)

        #expect(viewModel.continuation == nil)
        await #expect(throws: CancellationError.self) { try await run.value }
    }

    @Test("A deeplink pushes the confirm-email step onto the host stack")
    func pushedFlow_deeplink_pushesConfirmEmail() {
        let stack = HostStack(steps: [.intro])
        let viewModel = makePushedFlow(on: stack)

        viewModel.applyDeeplinkVerification(VerificationDescription(email: "a@b.c", code: "123456"))

        #expect(stack.steps == [.intro, .confirmEmailCode])
        #expect(viewModel.emailVerifier.enteredEmail == "a@b.c")
        // The sheet-owned path stays out of it while the flow is pushed.
        #expect(viewModel.verificationPath.isEmpty)
    }

    @Test("A repeat deeplink doesn't stack a second confirm-email step")
    func pushedFlow_repeatDeeplink_doesNotPushTwice() {
        let stack = HostStack(steps: [.intro])
        let viewModel = makePushedFlow(on: stack)
        let verification = VerificationDescription(email: "a@b.c", code: "123456")

        viewModel.applyDeeplinkVerification(verification)
        viewModel.applyDeeplinkVerification(verification)

        #expect(stack.steps == [.intro, .confirmEmailCode])
    }
}
