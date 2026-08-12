//
//  CameraPromptView.swift
//  Code
//

import SwiftUI
import AVFoundation
import FlipcashUI

/// The call to action shown in place of the camera viewport when the camera
/// isn't running, derived from authorization status and the auto-start
/// preference.
nonisolated enum CameraPrompt: Equatable {

    /// Access hasn't been requested; the action runs the system permission
    /// prompt. App Review requires a neutral label ("Continue"/"Next") on a
    /// button that gates a permission prompt — never one implying the camera
    /// starts.
    case requestPermission

    /// Access is denied or restricted; the action opens the app's Settings
    /// page.
    case openSettings

    /// Access is granted but auto-start is off; the action starts the camera.
    case startCamera

    /// Returns `nil` when the camera viewport should be running instead of a
    /// prompt.
    init?(status: AVAuthorizationStatus, cameraEnabled: Bool) {
        switch status {
        case .notDetermined:
            self = .requestPermission
        case .denied, .restricted:
            self = .openSettings
        case .authorized:
            if cameraEnabled {
                return nil
            }
            self = .startCamera
        @unknown default:
            self = .openSettings
        }
    }

    /// The explanatory text shown above the action button. `embedded` is the v2
    /// tab-bar UI, where the scanner is framed around tip cards rather than the
    /// v1 cash-grab wording.
    func message(embedded: Bool) -> String {
        switch self {
        case .requestPermission:
            embedded ? "Start your camera to scan a Tip Card"
                     : "Flipcash uses your camera to scan and grab cash"
        case .openSettings:
            embedded ? "Turn on Camera in Settings to scan a Tip Card"
                     : "You need to turn on Camera in Settings to scan Codes"
        case .startCamera:
            embedded ? "Start your camera to scan a Tip Card"
                     : "You need to start your camera to grab cash"
        }
    }

    /// The label of the prompt's single action button.
    var buttonTitle: String {
        switch self {
        case .requestPermission:
            "Continue"
        case .openSettings:
            "Open Settings"
        case .startCamera:
            "Start Camera"
        }
    }
}

/// Full-screen prompt pairing a ``CameraPrompt``'s message and button with the
/// action supplied by the host screen.
struct CameraPromptView: View {

    let prompt: CameraPrompt
    /// Whether shown inside the v2 tab-bar UI (affects the permission copy).
    var embedded: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Text(prompt.message(embedded: embedded))
                .frame(maxWidth: 260)
                .multilineTextAlignment(.center)

            BubbleButton(text: prompt.buttonTitle, action: action)
        }
        .padding(40)
        .font(.appTextSmall)
        .foregroundStyle(.textMain)
    }
}
