//
//  OnboardingViewModelTests.swift
//  FlipcashTests
//

import Contacts
import Testing
@testable import Flipcash

@Suite("OnboardingViewModel.destinationAfterPhoneStep(contactsStatus:)")
struct OnboardingViewModelDestinationAfterPhoneStepTests {

    private static let cases: [(CNAuthorizationStatus, OnboardingPath?)] = [
        (.notDetermined, .contactsPermissions),
        (.authorized,    nil),
        (.denied,        nil),
        (.restricted,    nil),
        (.limited,       nil),
    ]

    @Test(
        "Only .notDetermined routes to .contactsPermissions; every other status falls through",
        arguments: cases,
    )
    func routes(status: CNAuthorizationStatus, expected: OnboardingPath?) {
        #expect(OnboardingViewModel.destinationAfterPhoneStep(contactsStatus: status) == expected)
    }
}
