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
/// between the back and front lenses.
///
/// Separate from FlipcashUI's `CameraSession`, which wires only video-data and metadata outputs for
/// scanning and has no still-photo output.
@Observable
final class ChatPhotoCamera {

    /// Why the camera could not be set up.
    enum SetupError: Error {
        /// The device has no camera at the requested position, as on the simulator.
        case deviceUnavailable
        /// The session refused the camera's input or the photo output.
        case configurationRejected
    }

    /// The lens the session is capturing from.
    private(set) var position: AVCaptureDevice.Position = .back

    /// Whether a shutter press is still being processed.
    private(set) var isCapturing = false

    @ObservationIgnored let session = AVCaptureSession()

    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.flipcash.chat-camera.session")
    @ObservationIgnored private var input: AVCaptureDeviceInput?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    // The output holds its delegate weakly; each capture keeps its own alive until it finishes.
    @ObservationIgnored private var pendingCaptures: [Int64: PhotoCaptureDelegate] = [:]

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

    // MARK: - Session -

    /// Adds the photo output and the current lens to the session; a no-op once configured.
    func configure() throws {
        guard input == nil else { return }

        session.beginConfiguration()
        // An uncommitted session crashes on stopRunning(), so commit on every exit.
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo
        guard session.canAddOutput(output) else {
            throw SetupError.configurationRejected
        }
        session.addOutput(output)
        try attachInput(for: position)
    }

    /// Starts the session off the main thread; `startRunning()` blocks until frames flow.
    func start() {
        let session = session
        sessionQueue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    /// Stops the session off the main thread.
    func stop() {
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
        self.input = input
        self.position = position
        // The app is portrait-locked, so the interface can't say how the phone is held; the
        // coordinator reads the device's physical orientation for the photo's EXIF.
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }

    // MARK: - Capture -

    /// Returns the next photo from the running session, or `nil` if the session isn't running or
    /// the capture failed.
    func capture() async -> UIImage? {
        guard session.isRunning, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let settings = AVCapturePhotoSettings()
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

        // `UIImage(data:)` carries the EXIF orientation into `imageOrientation`, which the uploader
        // bakes into the pixels before encoding.
        return data.flatMap(UIImage.init(data:))
    }
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
