//
//  Regression_legacyTokenAcceptance.swift
//  FlipcashTests
//
//  After unification, the WithdrawKind enum gates whether token accounts are
//  accepted: .sameMint accepts both .owner and .token (legacy IntentWithdraw
//  tolerates token accounts server-side); .usdfToUsdc accepts only .owner
//  because the StatefulSwap stablecoin RPC requires a 32-byte owner pubkey.
//  This file proves the divergence is preserved by the kind-driven dispatch.
//

import Foundation
import Testing
import FlipcashCore
@testable import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: WithdrawKind preserves legacy .token acceptance + USDF .token rejection")
struct Regression_legacyTokenAcceptance {

    // MARK: - Legacy flow: .token accepted

    @Test("Legacy flow: .token accountType with isValid=true allows canCompleteWithdrawal")
    func legacyFlow_tokenAccountType_canCompleteWithdrawal() throws {
        let (container, balance) = try WithdrawViewModelTestHelpers.makeUSDFFixture()
        let vm = WithdrawViewModel(container: .mock, sessionContainer: container)
        vm.kind = .sameMint(balance)
        vm.enteredAmount = "5.00"
        vm.enteredAddress = "11111111111111111111111111111111"
        // Bypass the debounced fetch: supply metadata with .token kind directly.
        vm.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        // Legacy flow has no kind restriction — .token must be accepted.
        #expect(
            vm.canCompleteWithdrawal == true,
            "Legacy WithdrawViewModel must accept .token accountType — the USDF flow's .owner-only rule is USDF-specific"
        )
    }

    @Test("Legacy flow: .owner accountType with isValid=true also allows canCompleteWithdrawal")
    func legacyFlow_ownerAccountType_canCompleteWithdrawal() throws {
        let (container, balance) = try WithdrawViewModelTestHelpers.makeUSDFFixture()
        let vm = WithdrawViewModel(container: .mock, sessionContainer: container)
        vm.kind = .sameMint(balance)
        vm.enteredAmount = "5.00"
        vm.enteredAddress = "11111111111111111111111111111111"
        vm.destinationMetadata = DestinationMetadata(
            kind: .owner,
            destination: try PublicKey(base58: "11111111111111111111111111111111"),
            mint: .usdf,
            isValid: true,
            requiresInitialization: false,
            fee: .zero(mint: .usdf)
        )

        // Legacy flow accepts .owner as well.
        #expect(vm.canCompleteWithdrawal == true)
    }

    // MARK: - USDF flow: .token rejected (divergence anchor)

    @Test("USDF flow: .token accountType is rejected even when isValid=true")
    func usdfFlow_tokenAccountType_cannotCompleteWithdrawal() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(quarks: 100_000_000)
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .usdfToUsdc(usdf)
        viewModel.enteredAmount = "50"
        viewModel.enteredAddress = "11111111111111111111111111111111"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            kind: .token, isValid: true
        )

        // hasSufficientFunds passes (holdings seeded above), so the kind gate
        // is the deciding factor — .token must be blocked by the blacklist.
        #expect(
            viewModel.canCompleteWithdrawal == false,
            "Unified VM with .usdfToUsdc kind must reject .token accountType — only owner pubkeys are valid for the swap RPC"
        )
    }

    // MARK: - .unknown kind: no kind gate (blocked by isValid=false in production)

    @Test("Legacy flow accepts .unknown when isValid=true (no kind gate)")
    func legacyFlow_unknownAccountType_withValid_isAccepted() throws {
        let (container, balance) = try WithdrawViewModelTestHelpers.makeUSDFFixture()
        let vm = WithdrawViewModel(container: .mock, sessionContainer: container)
        vm.kind = .sameMint(balance)
        vm.enteredAmount = "5.00"
        vm.enteredAddress = "11111111111111111111111111111111"
        vm.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            kind: .unknown,
            isValid: true
        )

        #expect(
            vm.canCompleteWithdrawal == true,
            "Legacy WithdrawViewModel has no kind gate — accepts any kind when isValid=true"
        )
    }

}
