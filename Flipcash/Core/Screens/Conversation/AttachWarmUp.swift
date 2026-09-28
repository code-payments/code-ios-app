//
//  AttachWarmUp.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import AVFoundation
import Observation

/// Gets the camera running while the attach panel is up, so the camera card opens on a live frame
/// instead of waiting for the session to configure and start.
///
/// Warm while the panel is up or the camera card is; cold otherwise, so no capture session runs, and
/// the camera light stays off, while the menu is closed. Never asks for camera access: a camera that
/// hasn't been granted is left for the card to ask about.
@MainActor
@Observable
final class AttachWarmUp {

    /// Whether the panel or a card is up, and the camera with it if access allows.
    private(set) var isWarm = false

    @ObservationIgnored private var warmCamera: ChatPhotoCamera?
    @ObservationIgnored private let cameraAccess: () -> AVAuthorizationStatus

    init(cameraAccess: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) }) {
        self.cameraAccess = cameraAccess
    }

    /// The camera the card shows, made on first use and kept for the screen's lifetime.
    var camera: ChatPhotoCamera {
        if let warmCamera {
            return warmCamera
        }
        let camera = ChatPhotoCamera()
        warmCamera = camera
        return camera
    }

    /// Whether the camera has been made. A chat whose attach menu is never opened never makes one.
    var hasCamera: Bool { warmCamera != nil }

    /// Whether camera access is granted, so the camera can be mounted without asking for it.
    var cameraIsAuthorized: Bool { cameraAccess() == .authorized }

    /// The longest a card waits for its content before opening anyway.
    static let readinessBudget: Duration = .milliseconds(150)

    /// How long the inline picker has to have been mounted before its grid counts as drawn. The picker
    /// is remote and reports nothing, so this stands in for a signal.
    static let pickerLead: Duration = .milliseconds(300)

    /// When the surface's inline photo picker was mounted, while it is.
    @ObservationIgnored private(set) var pickerMountedAt: ContinuousClock.Instant?

    /// Records that the surface mounted its inline photo picker.
    func pickerDidMount() {
        pickerMountedAt = .now
    }

    /// Records that the surface took its inline photo picker down.
    func pickerDidUnmount() {
        pickerMountedAt = nil
    }

    /// Whether `item`'s card content is ready to be revealed at `now`: the camera running, or the
    /// picker mounted for ``pickerLead``. A camera without access has nothing to wait for, since its
    /// card asks for access instead.
    func isReady(for item: AttachMenuItem, at now: ContinuousClock.Instant = .now) -> Bool {
        switch item {
        case .cash:
            return true
        case .camera:
            return !cameraIsAuthorized || (warmCamera?.isRunning ?? false)
        case .photos:
            guard let pickerMountedAt else { return false }
            return now - pickerMountedAt >= Self.pickerLead
        }
    }

    /// Runs `body` once `item`'s card content is ready, or after ``readinessBudget`` at the most, so
    /// the card never opens empty for want of a few frames and never waits long for content that is
    /// slow to come.
    func whenReady(for item: AttachMenuItem, _ body: @escaping @MainActor () -> Void) {
        guard !isReady(for: item) else {
            body()
            return
        }
        let deadline = ContinuousClock.now + Self.readinessBudget
        Task { @MainActor [weak self] in
            while let self, !self.isReady(for: item), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(16))
            }
            body()
        }
    }

    /// Starts warming when `wanted` and stops when not, as the panel and the cards come and go.
    func update(wanted: Bool) {
        if wanted {
            warm()
        } else {
            cool()
        }
    }

    private func warm() {
        guard !isWarm else { return }
        isWarm = true
        guard cameraAccess() == .authorized else { return }
        let camera = camera
        Task { try? await camera.prepare() }
    }

    private func cool() {
        guard isWarm else { return }
        isWarm = false
        warmCamera?.stop()
    }
}
