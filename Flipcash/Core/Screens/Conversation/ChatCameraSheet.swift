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

/// A photo the chat camera took, with a copy decoded at the viewfinder's size for the chip it
/// shrinks into.
struct ChatCameraCapture {
    let image: UIImage
    let preview: UIImage?
}

/// The attach menu's Camera: a rounded viewfinder with a back chevron, a shutter, and a "…" button
/// that unfolds the flash and lens flip above itself, sized by its host as an ``AttachCard``.
///
/// Asks for camera access on first use, since opening the camera is the request. A capture hands
/// the photo to `onCapture`; the host stages it and collapses the camera.
struct ChatCameraSheet: View {

    /// The camera, owned by ``AttachWarmUp`` so it can already be running when this appears.
    let camera: ChatPhotoCamera
    let onCapture: (ChatCameraCapture) -> Void
    let onCancel: () -> Void

    /// The viewfinder's size in points, for decoding the capture's preview at a size that stays
    /// sharp for the whole shrink into its chip.
    @State private var viewfinderSize: CGSize = .zero

    @State private var authorizer = CameraAuthorizer()
    @State private var isUnavailable = false
    /// Whether the flash and flip buttons are unfolded above "…".
    @State private var showsMoreControls = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let controlSize: CGFloat = 44

    var body: some View {
        let phase = ChatCameraPhase(status: authorizer.status)
        let isLive = phase == .live && !isUnavailable
        ZStack {
            switch phase {
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
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { viewfinderSize = $0 }
        .background(Color.backgroundMain)
        // On every phase, so the way back is there while access is asked for or denied too.
        .overlay(alignment: .bottom) {
            controls(isLive: isLive)
        }
    }

    private var viewfinder: some View {
        ChatCameraPreview(session: camera.session)
            // Already running when the panel warmed it; this only catches a camera granted just now.
            // The warm-up stops it once the card is gone.
            .task {
                do {
                    try await camera.prepare()
                } catch {
                    isUnavailable = true
                }
            }
    }

    /// Back on the left, the shutter on the centre line, and "…" on the right; the shutter and "…"
    /// only while the viewfinder runs.
    private func controls(isLive: Bool) -> some View {
        HStack {
            backButton
            Spacer()
            if isLive {
                shutter
            }
            Spacer()
            if isLive {
                moreButton
            } else {
                // Balances the back button, so nothing shifts as the viewfinder comes up.
                Color.clear
                    .frame(width: Self.controlSize, height: Self.controlSize)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var shutter: some View {
        Button {
            Task {
                guard let image = await camera.capture() else { return }
                // Decoded off the main thread before the hand-off, so the chip the capture
                // shrinks into has pixels on its first frame.
                let scale = UITraitCollection.current.displayScale
                // Square on the longer side: the thumbnail keeps the photo's aspect, and a
                // portrait capture fitted into the wide viewfinder would come out small.
                let side = max(viewfinderSize.width, viewfinderSize.height) * scale
                let preview = side > 0 ? await image.byPreparingThumbnail(ofSize: CGSize(width: side, height: side)) : nil
                onCapture(ChatCameraCapture(image: image, preview: preview))
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
    }

    /// "…", turning into × while the flash and flip stand unfolded in a column above it.
    private var moreButton: some View {
        Button {
            withAnimation(ChatMotion.attachPanel.animation) {
                showsMoreControls.toggle()
            }
        } label: {
            ChatCameraControlLabel(systemImage: showsMoreControls ? "xmark" : "ellipsis")
                .overlay(alignment: .topTrailing) {
                    if !showsMoreControls {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: -2, y: 2)
                            .transition(.opacity)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsMoreControls ? "Hide camera controls" : "More camera controls")
        .accessibilityIdentifier("chat-camera-more")
        // An overlay, so unfolding the column leaves the row where it is.
        .overlay(alignment: .bottom) {
            if showsMoreControls {
                VStack(spacing: 12) {
                    if camera.isFlashAvailable {
                        flashButton
                    }
                    flipButton
                }
                .fixedSize()
                .padding(.bottom, Self.controlSize + 12)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: ChatMotion.attachPanelEnterScale, anchor: .bottom).combined(with: .opacity)
                )
            }
        }
    }

    private var flashButton: some View {
        let isOn = camera.flashMode == .on
        return Button {
            camera.toggleFlash()
        } label: {
            ChatCameraControlLabel(systemImage: isOn ? "bolt.fill" : "bolt.slash.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Flash")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityIdentifier("chat-camera-flash")
    }

    private var flipButton: some View {
        Button {
            camera.flip()
        } label: {
            ChatCameraControlLabel(systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(camera.position == .front ? "Use back camera" : "Use front camera")
        .accessibilityIdentifier("chat-camera-flip")
    }

    private var backButton: some View {
        Button(action: onCancel) {
            ChatCameraControlLabel(systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to attach menu")
        .accessibilityIdentifier("chat-camera-back")
    }
}

/// A round control over the viewfinder: a white glyph on a dimmed disc.
private struct ChatCameraControlLabel: View {

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.default(size: 17, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.black.opacity(0.35)))
            .contentShape(Circle())
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
