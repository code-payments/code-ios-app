//
//  AttachWarmUpTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import AVFoundation
@testable import Flipcash

@MainActor
@Suite("Attach warm-up")
struct AttachWarmUpTests {

    @Test("Without camera access the warm-up makes no camera, so nothing can prompt", arguments: [
        AVAuthorizationStatus.notDetermined, .denied, .restricted,
    ])
    func noAccessMakesNoCamera(status: AVAuthorizationStatus) {
        let warmUp = AttachWarmUp(cameraAccess: { status })
        warmUp.update(wanted: true)
        #expect(warmUp.isWarm)
        #expect(!warmUp.hasCamera)
    }

    @Test("With access the panel opening makes the camera and starts preparing it")
    func accessWarmsCamera() {
        let warmUp = AttachWarmUp(cameraAccess: { .authorized })
        warmUp.update(wanted: true)
        #expect(warmUp.hasCamera)
    }

    @Test("Closing the panel without a choice cools the warm-up")
    func closingCools() {
        let warmUp = AttachWarmUp(cameraAccess: { .authorized })
        warmUp.update(wanted: true)
        warmUp.update(wanted: false)
        #expect(!warmUp.isWarm)
    }

    @Test("A chat whose menu never opens never makes a camera")
    func idleMakesNoCamera() {
        let warmUp = AttachWarmUp(cameraAccess: { .authorized })
        warmUp.update(wanted: false)
        #expect(!warmUp.hasCamera)
        #expect(!warmUp.isWarm)
    }

    @Test("Photos is ready once the picker has been mounted for its lead, and not before")
    func photosReadyAfterLead() {
        let warmUp = AttachWarmUp(cameraAccess: { .denied })
        #expect(!warmUp.isReady(for: .photos))

        warmUp.pickerDidMount()
        let mounted = try! #require(warmUp.pickerMountedAt)
        #expect(!warmUp.isReady(for: .photos, at: mounted))
        #expect(warmUp.isReady(for: .photos, at: mounted + AttachWarmUp.pickerLead))

        warmUp.pickerDidUnmount()
        #expect(!warmUp.isReady(for: .photos))
    }

    @Test("A camera without access is ready at once: its card asks, nothing is mounted to wait on")
    func cameraWithoutAccessIsReady() {
        let warmUp = AttachWarmUp(cameraAccess: { .notDetermined })
        #expect(warmUp.isReady(for: .camera))
        #expect(warmUp.isReady(for: .cash))
    }

    @Test("A card whose content is late opens within the readiness budget anyway")
    func whenReadyGivesUpAtBudget() async {
        let warmUp = AttachWarmUp(cameraAccess: { .denied })
        let start = ContinuousClock.now
        await withCheckedContinuation { continuation in
            warmUp.whenReady(for: .photos) { continuation.resume() }
        }
        let waited = ContinuousClock.now - start
        #expect(waited >= AttachWarmUp.readinessBudget)
        #expect(waited < .seconds(1))
    }
}
