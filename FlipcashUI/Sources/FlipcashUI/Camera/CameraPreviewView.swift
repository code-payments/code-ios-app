//
//  CameraPreviewView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import UIKit
import SwiftUI
import AVKit

public struct CameraViewport: View {

    @State private var focusPoints: [CGPoint] = []

    private let session: AnyCameraSession
    private let enableGestures: Bool

    public init(session: AnyCameraSession, enableGestures: Bool) {
        self.session = session
        self.enableGestures = enableGestures
    }

    public var body: some View {
        ZStack {
            CameraPreviewView(
                session: session,
                enableGestures: enableGestures,
                focusEvent: didFocus
            )

            GeometryReader { geometry in
                ForEach(Array(focusPoints), id: \.self) { point in
                    let anchor = UnitPoint(
                        x: point.x / geometry.size.width,
                        y: point.y / geometry.size.height
                    )

                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1.0)
                        .frame(width: 40, height: 40)
                        .position(point)
                        .id("\(point.id):1")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(
                                with: .scale(
                                    scale: 1.9,
                                    anchor: anchor
                                )
                            ),
                            removal: .opacity
                        ))

                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 35, height: 35)
                        .position(point)
                        .id("\(point.id):2")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(
                                with: .scale(
                                    scale: 0.5,
                                    anchor: anchor
                                )
                            ),
                            removal: .opacity
                        ))
                }
            }
            .animation(.spring(dampingFraction: 0.5).speed(1.2), value: focusPoints)
        }
        .background(Color.backgroundMain)
        .edgesIgnoringSafeArea(.all)
    }

    private func didFocus(point: CGPoint) {
        removeAllFocusPoints()

        let roundedPoint = point.rounded
        addFocus(roundedPoint)
        Task {
            try await Task.delay(milliseconds: 750)
            removeFocus(roundedPoint)
        }
    }

    private func addFocus(_ point: CGPoint) {
        focusPoints.append(point)
    }

    private func removeFocus(_ point: CGPoint) {
        focusPoints.removeAll { $0.id == point.id }
    }

    private func removeAllFocusPoints() {
        focusPoints.removeAll()
    }
}

public struct CameraPreviewView: View, UIViewRepresentable {

    private let session: AnyCameraSession
    private let enableGestures: Bool
    private let focusEvent: (CGPoint) -> Void

    public init(session: AnyCameraSession, enableGestures: Bool, focusEvent: @escaping (CGPoint) -> Void) {
        self.session = session
        self.enableGestures = enableGestures
        self.focusEvent = focusEvent
    }

    public func makeUIView(context: Context) -> _CameraPreviewView {
        let view = _CameraPreviewView.shared
        view.focusEvent = focusEvent
        updateUIView(view, context: context)
        return view
    }

    public func updateUIView(_ uiView: _CameraPreviewView, context: Context) {
        uiView.session = session
        uiView.setGestures(enabled: enableGestures)
    }
}

// MARK: - _CameraPreviewView -

public class _CameraPreviewView: UIView {

    static let shared = _CameraPreviewView()

    var session: AnyCameraSession? {
        didSet {
            previewLayer.session = session?.session

            setNeedsLayout()
        }
    }

    var focusEvent: (CGPoint) -> Void = { _ in }

    private var currentDevice: AVCaptureDevice? {
        previewLayer.session?.inputs.compactMap {
            if let input = $0 as? AVCaptureDeviceInput {
                return input.device
            }
            return nil
        }.first
    }

    private let previewLayer = AVCaptureVideoPreviewLayer()

    private let pinchGesture = UIPinchGestureRecognizer()
    private let tapGesture = UITapGestureRecognizer()

    private var gestureZoomFactor: CGFloat = 1.0

    // MARK: - Init -

    required init?(coder: NSCoder) { fatalError() }

    override init(frame: CGRect) {
        super.init(frame: frame)

        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        pinchGesture.addTarget(self, action: #selector(handlePinch(gesture:)))
        addGestureRecognizer(pinchGesture)

        tapGesture.addTarget(self, action: #selector(handleTapToFocus(gesture:)))
        addGestureRecognizer(tapGesture)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        previewLayer.bounds   = bounds
        previewLayer.position = CGPoint(
            x: bounds.width  * 0.5,
            y: bounds.height * 0.5
        )
    }

    func setGestures(enabled: Bool) {
        pinchGesture.isEnabled = enabled
        tapGesture.isEnabled = enabled
    }

    @objc private func handleTapToFocus(gesture: UITapGestureRecognizer) {
        guard let device = currentDevice else {
            return
        }

        let location   = gesture.location(in: gesture.view)
        let bounds     = gesture.view?.bounds ?? .zero
        let focusPoint = CGPoint(
            x: location.y / bounds.height,
            y: 1 - (location.x / bounds.width)
        )

        self.focusEvent(location)

        setFocusPoint(
            normalizedPoint: focusPoint,
            device: device
        )
    }

    @objc private func handlePinch(gesture: UIPinchGestureRecognizer) {
        guard let device = currentDevice else {
            return
        }

        switch gesture.state {
        case .began:
            gestureZoomFactor = device.videoZoomFactor

        case .changed:
            // Mild power curve so larger pinches cover more range per finger travel.
            let amplified = pow(gesture.scale, 1.3)
            setZoomFactor(gestureZoomFactor * amplified, device: device)

        case .ended, .cancelled:
            setZoomFactor(wideStartZoomFactor(for: device), device: device)

        default:
            break
        }
    }

    private func setZoomFactor(_ factor: CGFloat, device: AVCaptureDevice) {
        let newZoomFactor = clamp(factor, device: device)
        do {
            try device.lockForConfiguration()

            device.videoZoomFactor = newZoomFactor

            device.unlockForConfiguration()
        } catch {}
    }

    private func setFocusPoint(normalizedPoint: CGPoint, device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = normalizedPoint
                device.focusMode = .continuousAutoFocus
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = normalizedPoint
                device.exposureMode = .continuousAutoExposure
            }

            device.unlockForConfiguration()
        } catch {}
    }

    private func clamp(_ zoomFactor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        let lower = device.minAvailableVideoZoomFactor
        // 20× gives meaningful headroom past the longest optical lens on every
        // current iPhone, hard-capped by what the device actually reports.
        let upper = min(device.maxAvailableVideoZoomFactor, 20.0)
        return min(max(zoomFactor, lower), upper)
    }
}

extension _CameraPreviewView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == tapGesture || otherGestureRecognizer == tapGesture {
            return true
        }
        return false
    }
}

extension CGPoint: @retroactive Hashable, @retroactive Identifiable {

    public var id: String {
        "\(Int(x)):\(Int(y))"
    }

    public var rounded: CGPoint {
        CGPoint(
            x: round(x),
            y: round(y)
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#endif
