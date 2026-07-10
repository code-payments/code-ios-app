//
//  CameraPromptTests.swift
//  FlipcashTests
//

import AVFoundation
import Testing
@testable import Flipcash

@Suite("CameraPrompt")
struct CameraPromptTests {

    @Test(
        "Undetermined permission prompts with a neutral Continue",
        arguments: [true, false],
    )
    func prompt_notDetermined_offersContinue(cameraEnabled: Bool) throws {
        let prompt = try #require(CameraPrompt(status: .notDetermined, cameraEnabled: cameraEnabled))
        #expect(prompt == .requestPermission)
        #expect(prompt.buttonTitle == "Continue")
        #expect(prompt.message == "Flipcash uses your camera to scan and grab cash")
    }

    @Test(
        "Denied or restricted permission directs to Settings",
        arguments: [AVAuthorizationStatus.denied, .restricted], [true, false],
    )
    func prompt_deniedOrRestricted_directsToSettings(status: AVAuthorizationStatus, cameraEnabled: Bool) throws {
        let prompt = try #require(CameraPrompt(status: status, cameraEnabled: cameraEnabled))
        #expect(prompt == .openSettings)
        #expect(prompt.buttonTitle == "Open Settings")
        #expect(prompt.message == "You need to turn on Camera in Settings to scan Codes")
    }

    @Test("Authorized with auto-start off offers Start Camera")
    func prompt_authorizedCameraOff_offersStartCamera() throws {
        let prompt = try #require(CameraPrompt(status: .authorized, cameraEnabled: false))
        #expect(prompt == .startCamera)
        #expect(prompt.buttonTitle == "Start Camera")
        #expect(prompt.message == "You need to start your camera to grab cash")
    }

    @Test("Authorized with the camera running shows no prompt")
    func prompt_authorizedCameraOn_showsNoPrompt() {
        #expect(CameraPrompt(status: .authorized, cameraEnabled: true) == nil)
    }
}
