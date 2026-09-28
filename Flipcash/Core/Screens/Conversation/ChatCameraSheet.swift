//
//  ChatCameraSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import AVFoundation
import FlipcashUI

/// What the chat camera shows for a camera authorization status.
nonisolated enum ChatCameraPhase: Equatable {

    /// Access hasn't been asked for yet; the system prompt is up.
    case requestingAccess

    /// Access is granted; the viewfinder runs.
    case live

    /// Access is denied or restricted; the panel points to Settings.
    case denied

    init(status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .requestingAccess
        case .authorized:
            self = .live
        case .denied, .restricted:
            self = .denied
        @unknown default:
            self = .denied
        }
    }
}

/// The attach menu's Camera: a rounded viewfinder with a shutter, a lens flip, and a back chevron,
/// sized by its host to the keyboard's frame.
///
/// Asks for camera access on first use, since opening the camera is the request. A capture hands
/// the photo to `onCapture`; the host stages it and collapses the camera.
struct ChatCameraSheet: View {

    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var authorizer = CameraAuthorizer()
    @State private var camera = ChatPhotoCamera()
    @State private var isUnavailable = false

    private static let cornerRadius: CGFloat = 24

    var body: some View {
        ZStack {
            switch ChatCameraPhase(status: authorizer.status) {
            case .requestingAccess:
                ProgressView()
                    .task { _ = try? await authorizer.authorize() }
            case .denied:
                CameraPromptView(
                    prompt: .openSettings,
                    message: "Turn on Camera in Settings to send photos"
                ) {
                    URL.openSettings()
                }
            case .live:
                if isUnavailable {
                    Text("Camera unavailable")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    viewfinder
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundMain)
        .overlay(alignment: .topLeading) {
            backButton
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private var viewfinder: some View {
        ChatCameraPreview(session: camera.session)
            .overlay(alignment: .bottom) {
                controls
            }
            .task {
                do {
                    try camera.configure()
                    camera.start()
                } catch {
                    isUnavailable = true
                }
            }
            .onDisappear {
                camera.stop()
            }
    }

    private var controls: some View {
        HStack {
            // Balances the flip button so the shutter sits on the centre line.
            Color.clear
                .frame(width: 44, height: 44)
            Spacer()
            Button {
                Task {
                    if let image = await camera.capture() {
                        onCapture(image)
                    }
                }
            } label: {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .padding(-2)
                    .overlay {
                        Circle()
                            .fill(Color.white)
                            .padding(6)
                    }
                    .frame(width: 68, height: 68)
            }
            .buttonStyle(.plain)
            .disabled(camera.isCapturing)
            .accessibilityLabel("Take photo")
            .accessibilityIdentifier("chat-camera-shutter")
            Spacer()
            Button {
                camera.flip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.default(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(camera.position == .front ? "Use back camera" : "Use front camera")
            .accessibilityIdentifier("chat-camera-flip")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var backButton: some View {
        Button(action: onCancel) {
            Image(systemName: "chevron.left")
                .font(.default(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("Back to keyboard")
        .accessibilityIdentifier("chat-camera-back")
    }
}

// MARK: - ChatCameraPreview -

/// The live feed of a capture session, filling its frame.
///
/// Its own layer rather than FlipcashUI's `CameraViewport`: that view hands out one shared
/// `_CameraPreviewView`, and mounting it here would pull the scanner's preview out of its tab.
private struct ChatCameraPreview: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = UIColor(Color.backgroundMain)
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    final class PreviewView: UIView {

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // `layerClass` guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
