//
//  OnboardingNameViewModelTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("OnboardingNameViewModel")
struct OnboardingNameViewModelTests {

    @Test("A blank name is invalid, so Next stays gated")
    func blankName_isInvalid() {
        let viewModel = OnboardingNameViewModel(owner: .mock, flipClient: .mock)
        viewModel.displayName = "   "
        #expect(viewModel.validatedDisplayName == nil)
    }

    @Test("A name is trimmed of surrounding whitespace and accepted")
    func name_isTrimmedAndAccepted() {
        let viewModel = OnboardingNameViewModel(owner: .mock, flipClient: .mock)
        viewModel.displayName = "  Ada  "
        #expect(viewModel.validatedDisplayName == "Ada")
    }

    @Test("Remaining characters counts down from the scalar limit")
    func remainingCharacters_countsDown() {
        let viewModel = OnboardingNameViewModel(owner: .mock, flipClient: .mock)
        viewModel.displayName = "Ada"
        #expect(viewModel.remainingCharacters == DisplayNameValidator.maxScalars - 3)
    }
}
