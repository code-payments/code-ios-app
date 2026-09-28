//
//  ChatCameraSlot.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import Observation

/// Whether the inline camera holds the keyboard's place under the composer, and how tall that
/// place is.
@MainActor
@Observable
final class ChatCameraSlot {

    /// The height the camera takes before a keyboard has risen on this screen.
    static let fallbackHeight: CGFloat = 300

    /// Whether the camera is up in the keyboard's place.
    private(set) var isOpen = false

    /// The keyboard's height above the bottom safe area, the last time it rose.
    private(set) var height: CGFloat = fallbackHeight

    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let info = notification.userInfo
            let endFrame = info?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            let isLocal = info?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true
            MainActor.assumeIsolated {
                guard isLocal, let endFrame, !endFrame.isEmpty else { return }
                let safeAreaBottom = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
                self?.keyboardWillShow(height: endFrame.height, safeAreaBottom: safeAreaBottom)
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Puts the camera up in the keyboard's place.
    func open() {
        guard !isOpen else { return }
        isOpen = true
    }

    /// Takes the camera down.
    func close() {
        guard isOpen else { return }
        isOpen = false
    }

    /// Records a keyboard `height` tall rising over a window whose bottom safe area is
    /// `safeAreaBottom`, and closes the camera, since the keyboard is taking its place back.
    func keyboardWillShow(height keyboardHeight: CGFloat, safeAreaBottom: CGFloat) {
        let slotHeight = keyboardHeight - safeAreaBottom
        if slotHeight > 0, slotHeight != height {
            height = slotHeight
        }
        close()
    }
}
