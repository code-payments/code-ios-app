//
//  OnboardingViewModelTests.swift
//  FlipcashTests
//

import Contacts
import Testing
@testable import Flipcash

@Suite("OnboardingViewModel.destinationAfterPhoneStep(contactsStatus:)")
struct OnboardingViewModelDestinationAfterPhoneStepTests {

    @Test(".notDetermined routes to the contacts permission step")
    func notDeterminedRoutesToContactsPermissions() {
        #expect(OnboardingViewModel.destinationAfterPhoneStep(contactsStatus: .notDetermined) == .contactsPermissions)
    }

    @Test(".authorized falls through (nil) so the post-contacts flow runs")
    func authorizedFallsThrough() {
        #expect(OnboardingViewModel.destinationAfterPhoneStep(contactsStatus: .authorized) == nil)
    }

    @Test(".denied falls through")
    func deniedFallsThrough() {
        #expect(OnboardingViewModel.destinationAfterPhoneStep(contactsStatus: .denied) == nil)
    }

    @Test(".restricted falls through")
    func restrictedFallsThrough() {
        #expect(OnboardingViewModel.destinationAfterPhoneStep(contactsStatus: .restricted) == nil)
    }

    @Test(".limited falls through (treated as denied for v1)")
    func limitedFallsThrough() {
        #expect(OnboardingViewModel.destinationAfterPhoneStep(contactsStatus: .limited) == nil)
    }
}
