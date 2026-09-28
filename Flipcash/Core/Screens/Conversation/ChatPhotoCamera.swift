//
//  ChatPhotoCamera.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import Observation
// SAFETY: AVCaptureSession and AVCapturePhotoOutput are documented thread-safe, but AVFoundation
// has not adopted Sendable, so handing the session to the session queue trips compile-time
// warnings. Same exemption `CameraSession` takes.
// FOLLOW-UP: Remove once AVFoundation annotates the capture pipeline as Sendable.
@preconcurrency import AVFoundation

/// A still-photo camera for the chat composer: one capture session with a photo output, flippable
/// between the back and front lenses, with a flash the shutter fires when the lens supports it.
///
/// Separate from FlipcashUI's `CameraSession`, which wires only video-data and metadata outputs for
/// scanning and has no still-photo output.
@Observable
final class ChatPhotoCamera {

    /// Why the camera could not be set up.
    nonisolated enum SetupError: Error {
        /// The device has no camera at the requested position, as on the simulator.
        case deviceUnavailable
        /// The session refused the camera's input or the photo output.
        case configurationRejected
    }

    /// The lens the session is capturing from.
    private(set) var position: AVCaptureDevice.Position = .back

    /// Whether a shutter press is still being processed.
    private(set) var isCapturing = false

    /// The flash the next shot asks for. A lens that can't fire it shoots without.
    private(set) var flashMode: AVCaptureDevice.FlashMode = .off

    /// Whether the current lens can fire a flash.
    private(set) var isFlashAvailable = false

    /// Whether the session is delivering frames: from its start until ``stop()``.
    private(set) var isRunning = false

    @ObservationIgnored let session = AVCaptureSession()

    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.flipcash.chat-camera.session")
    @ObservationIgnored private var input: AVCaptureDeviceInput?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    // The output holds its delegate weakly; each capture keeps its own alive until it finishes.
    @ObservationIgnored private var pendingCaptures: [Int64: PhotoCaptureDelegate] = [:]
    /// The configuration in flight or done, shared by every caller of ``prepare()``.
    @ObservationIgnored private var configuring: Task<Void, Error>?
    /// Whether the session should be running. A ``stop()`` while ``prepare()`` is still configuring
    /// keeps the session from starting once it finishes.
    @ObservationIgnored private var wantsRunning = false

    // Same Swift 6.3 EarlyPerfInliner workaround `CameraSession` carries for @MainActor deinits.
    nonisolated deinit {}

    /// Returns the lens a flip moves to from `position`.
    nonisolated static func flipped(_ position: AVCaptureDevice.Position) -> AVCaptureDevice.Position {
        switch position {
        case .back:
            .front
        case .front, .unspecified:
            .back
        @unknown default:
            .back
        }
    }

    /// Returns the flash after `mode` in the toggle: off and on, nothing automatic.
    nonisolated static func toggled(_ mode: AVCaptureDevice.FlashMode) -> AVCaptureDevice.FlashMode {
        switch mode {
        case .off:
            .on
        case .on, .auto:
            .off
        @unknown default:
            .off
        }
    }

    /// Returns the flash a shot can ask for given what the output `supported`: `requested` if the
    /// output fires it, off otherwise. Asking an output for a mode it lacks raises an exception.
    nonisolated static func resolvedFlashMode(
        _ requested: AVCaptureDevice.FlashMode,
        supported: [AVCaptureDevice.FlashMode]
    ) -> AVCaptureDevice.FlashMode {
        supported.contains(requested) ? requested : .off
    }

    /// Switches the flash between off and on.
    func toggleFlash() {
        flashMode = Self.toggled(flashMode)
    }

    // MARK: - Session -

    /// Configures the session with the photo output and the current lens, then starts it, all off the
    /// main thread so the first frame can be live before the viewfinder is on screen. Configures once;
    /// later calls only start it again. Does not ask for camera access.
    func prepare() async throws {
        wantsRunning = true
        let configuring = configuring ?? Task { try await configureOffMain() }
        self.configuring = configuring
        do {
            try await configuring.value
        } catch {
            // So a later call, after access is granted, can try again.
            self.configuring = nil
            throw error
        }
        guard wantsRunning else { return }
        start()
    }

    private func configureOffMain() async throws {
        let session = session
        let output = output
        let position = position
        let configured = try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                continuation.resume(with: Result { try Self.configure(session, output: output, position: position) })
            }
        }
        adopt(configured, at: position)
    }

    /// Adds `output` and the `position` lens to `session`, returning the lens's input and whether it
    /// can fire a flash. Blocking; runs on the session queue.
    private nonisolated static func configure(
        _ session: AVCaptureSession,
        output: AVCapturePhotoOutput,
        position: AVCaptureDevice.Position
    ) throws -> ConfiguredInput {
        session.beginConfiguration()
        // An uncommitted session crashes on stopRunning(), so commit on every exit.
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo
        guard session.canAddOutput(output) else {
            throw SetupError.configurationRejected
        }
        session.addOutput(output)
        return try attach(position, to: session, output: output)
    }

    /// Adds the `position` lens to `session`, returning its input and whether `output` can fire a
    /// flash through it. Inside a configuration block.
    private nonisolated static func attach(
        _ position: AVCaptureDevice.Position,
        to session: AVCaptureSession,
        output: AVCapturePhotoOutput
    ) throws -> ConfiguredInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw SetupError.deviceUnavailable
        }
        guard
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw SetupError.configurationRejected
        }
        session.addInput(input)
        // Read after the input is attached: the output's supported modes follow the lens.
        return ConfiguredInput(input: input, isFlashAvailable: output.supportedFlashModes.contains(.on))
    }

    /// Records the lens `configured` attached at `position`.
    private func adopt(_ configured: ConfiguredInput, at position: AVCaptureDevice.Position) {
        input = configured.input
        self.position = position
        isFlashAvailable = configured.isFlashAvailable
        // The app is portrait-locked, so the interface can't say how the phone is held; the
        // coordinator reads the device's physical orientation for the photo's EXIF.
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: configured.input.device, previewLayer: nil)
    }

    /// Starts the session off the main thread; `startRunning()` blocks until frames flow.
    private func start() {
        let session = session
        sessionQueue.async { [weak self] in
            if !session.isRunning {
                session.startRunning()
            }
            let isRunning = session.isRunning
            Task { @MainActor [weak self] in
                guard let self, self.wantsRunning else { return }
                self.isRunning = isRunning
            }
        }
    }

    /// Stops the session off the main thread, or keeps one still being prepared from starting.
    func stop() {
        wantsRunning = false
        isRunning = false
        let session = session
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// Swaps to the other lens, keeping the current one if the other is missing.
    func flip() {
        guard input != nil else { return }
        let target = Self.flipped(position)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let previous = input
        if let previous {
            session.removeInput(previous)
        }
        do {
            try attachInput(for: target)
        } catch {
            if let previous, session.canAddInput(previous) {
                session.addInput(previous)
                input = previous
            }
        }
    }

    private func attachInput(for position: AVCaptureDevice.Position) throws {
        adopt(try Self.attach(position, to: session, output: output), at: position)
    }

    // MARK: - Capture -

    /// Returns the next photo from the running session, or `nil` if the session isn't running or
    /// the capture failed.
    func capture() async -> UIImage? {
        guard session.isRunning, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let settings = AVCapturePhotoSettings()
        // Resolved at the shot, not when the flash was toggled: a flip since then changes what the
        // output supports.
        settings.flashMode = Self.resolvedFlashMode(flashMode, supported: output.supportedFlashModes)
        if let connection = output.connection(with: .video), let rotationCoordinator {
            let angle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        let id = settings.uniqueID
        let data: Data? = await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate { continuation.resume(returning: $0) }
            pendingCaptures[id] = delegate
            output.capturePhoto(with: settings, delegate: delegate)
        }
        pendingCaptures[id] = nil

        guard let data else { return nil }
        return await ChatPhotoStaging.decode(data)
    }
}

/// The lens a configuration attached, carried back from the session queue.
private nonisolated struct ConfiguredInput {
    let input: AVCaptureDeviceInput
    let isFlashAvailable: Bool
}

// MARK: - PhotoCaptureDelegate -

// AVFoundation calls back on its own queue, so the delegate stays off the main actor, as
// `CameraSession`'s delegates do.
//
// SAFETY (`@unchecked Sendable`): the only stored property is an immutable `@Sendable` closure.
private nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    private let completion: @Sendable (Data?) -> Void

    init(completion: @escaping @Sendable (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}
