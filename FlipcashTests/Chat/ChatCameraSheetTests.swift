//
//  ChatCameraSheetTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import AVFoundation
import Testing
@testable import Flipcash

@MainActor
@Suite("Chat camera sheet")
struct ChatCameraSheetTests {

    @Test("First use asks for camera access")
    func notDeterminedRequestsAccess() {
        #expect(ChatCameraPhase(status: .notDetermined) == .requestingAccess)
    }

    @Test("Granted access shows the live camera")
    func authorizedIsLive() {
        #expect(ChatCameraPhase(status: .authorized) == .live)
    }

    @Test("Denied or restricted access shows the Settings prompt", arguments: [
        AVAuthorizationStatus.denied,
        .restricted,
    ])
    func refusedShowsSettingsPrompt(status: AVAuthorizationStatus) {
        #expect(ChatCameraPhase(status: status) == .denied)
    }

    @Test("A flip alternates between the back and front lenses", arguments: [
        (AVCaptureDevice.Position.back, AVCaptureDevice.Position.front),
        (.front, .back),
        (.unspecified, .back),
    ])
    func flipAlternatesLenses(from: AVCaptureDevice.Position, to: AVCaptureDevice.Position) {
        #expect(ChatPhotoCamera.flipped(from) == to)
    }

    @Test("The shutter on a camera that never started returns no photo")
    func captureBeforeStartReturnsNil() async {
        let camera = ChatPhotoCamera()
        #expect(await camera.capture() == nil)
    }
}
