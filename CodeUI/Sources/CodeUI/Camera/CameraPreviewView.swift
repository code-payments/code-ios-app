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
    private let panGesture = UIPanGestureRecognizer()//DragGestureRecognizer()
    
    private var gestureZoomFactor: CGFloat = 1.0
    
    private var displayLink: CADisplayLink?
    private var reverseStart: Date?
    private var isReversing: Bool = false {
        didSet {
            if isReversing {
                reverseStart = .now
            } else {
                reverseStart = nil
            }
        }
    }
    
    // MARK: - Init -

    required init?(coder: NSCoder) { fatalError() }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        displayLink = CADisplayLink(target: self, selector: #selector(refresh))
        displayLink?.preferredFrameRateRange = .init(minimum: 60, maximum: 60)
        displayLink?.add(to: .current, forMode: .common)
        
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        
        pinchGesture.addTarget(self, action: #selector(handlePinch(gesture:)))
        addGestureRecognizer(pinchGesture)
        
        panGesture.addTarget(self, action: #selector(handlePan(gesture:)))
        addGestureRecognizer(panGesture)
        
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
        panGesture.isEnabled = enabled
        tapGesture.isEnabled = enabled
    }
    
    @objc private func handleTapToFocus(gesture: UITapGestureRecognizer) {
        guard let device = currentDevice else {
            return
        }
        
        let location   = gesture.location(in: gesture.view)
        let bounds     = gesture.view?.bounds ?? .zero
        let focusPoint = CGPoint(
            x: 1.0 - (location.x / bounds.width),
            y: location.y / bounds.height
        )
        
        self.focusEvent(location)
        
        setFocusPoint(
            normalizedPoint: focusPoint,
            device: device
        )
    }
    
    @objc func refresh(link: CADisplayLink) {
        guard isReversing else {
            return
        }
        
        guard let currentDevice, let reverseStart else {
            return
        }
        
        let factor = currentDevice.videoZoomFactor
        
        guard factor > 1.01 else {
            setZoomFactor(1.0, device: currentDevice)
            isReversing = false
            return
        }
        
        func easeOut(easeIn: Bool = false, value: Double, from inputRange: ClosedRange<Double>, to outputRange: ClosedRange<Double>) -> Double {
            // Normalize the value to a 0 to 1 range
            let normalizedValue = (value - inputRange.lowerBound) / (inputRange.upperBound - inputRange.lowerBound)
            
            let easedValue: Double
            if easeIn {
                // easeInOut formula
                if normalizedValue < 0.5 {
                    easedValue = 4 * pow(normalizedValue, 3)
                } else {
                    easedValue = 1 - pow(-2 * normalizedValue + 2, 3) / 2
                }
                
            } else {
                // easeOut formula
                easedValue = 1 - pow(1 - normalizedValue, 3)
            }
            
            // Map the eased value to the output range
            let mappedValue = easedValue * (outputRange.upperBound - outputRange.lowerBound) + outputRange.lowerBound
            
            return mappedValue
        }
        
        let timeElapsed = Date.now.timeIntervalSince1970 - reverseStart.timeIntervalSince1970
        let factorToAnimate = gestureZoomFactor - 1.0
        let duration: Double = 0.3
        let factorDelta = easeOut(
            easeIn: false,
            value: timeElapsed,
            from: 0.0...duration,
            to:   0.0...factorToAnimate
        )
        
        setZoomFactor(gestureZoomFactor - factorDelta, device: currentDevice)
    }
    
    @objc private func handlePinch(gesture: UIPinchGestureRecognizer) {
        guard let device = currentDevice else {
            return
        }
        
        switch gesture.state {
        case .began:
            isReversing = false
            gestureZoomFactor = device.videoZoomFactor
            
        case .changed:
            setZoomFactor(gestureZoomFactor * gesture.scale, device: device)
            
        case .ended, .cancelled:
            gestureZoomFactor = device.videoZoomFactor
            isReversing = true
            
        default:
            break
        }
    }
    
    @objc private func handlePan(gesture: UIPanGestureRecognizer) {
        guard let device = currentDevice else {
            return
        }
        
        switch gesture.state {
        case .began:
            isReversing = false
            gestureZoomFactor = device.videoZoomFactor
            
        case .changed:
            let translation = gesture.translation(in: gesture.view)
            let dragAmount = translation.y / 50.0
            
            setZoomFactor(gestureZoomFactor - dragAmount, device: device)
            
        case .ended, .failed:
            gestureZoomFactor = device.videoZoomFactor
            isReversing = true
            
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
                device.focusMode = .autoFocus
            }
            
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = normalizedPoint
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
        } catch {}
    }
    
    private func clamp(_ zoomFactor: CGFloat, device: AVCaptureDevice) -> CGFloat {
        min(max(zoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
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

// MARK: - DragGesture -

private class DragGestureRecognizer: UIGestureRecognizer {
    
    private var initialTouch: LocalTouch?
    private var startingTouch: LocalTouch?
    private var currentTouch: LocalTouch?
    
    func translation() -> CGPoint {
        guard let start = startingTouch else {
            return .zero
        }
        
        guard let current = currentTouch else {
            return .zero
        }
        
        let startLocation   = start.location
        let currentLocation = current.location
        
        return CGPoint(
            x: currentLocation.x - startLocation.x,
            y: currentLocation.y - startLocation.y
        )
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        guard touches.count == 1 else {
            self.state = .failed
            return
        }
        
        let touch = touches.first!
        
        let maxDelta: TimeInterval = 0.3
        let maxDistance: CGFloat = 20
        
        guard let initialTouch, touch.timestamp - initialTouch.timestamp < maxDelta else {
            initialTouch = touch.localTouch
            return
        }
        
        guard initialTouch.distance(to: touch.localTouch) < maxDistance else {
            self.state = .failed
            return
        }
        
        startingTouch = touch.localTouch
        currentTouch = touch.localTouch
        state = .began
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        
        if state == .began || state == .changed {
            if let firstTouch = touches.first {
                currentTouch = firstTouch.localTouch
            }
            
            state = .changed
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        
        if let firstTouch = touches.first {
            currentTouch = firstTouch.localTouch
        }
        
        if state == .changed {
            state = .ended
        } else {
            state = .failed
        }
        
        reset()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        
        state = .cancelled
        
        reset()
    }
    
    override func reset() {
        super.reset()
    }
}

private struct LocalTouch {
    
    let timestamp: TimeInterval
    let location: CGPoint
    
    func distance(to touch: LocalTouch) -> CGFloat {
        hypot(
            location.x - touch.location.x,
            location.y - touch.location.y
        )
    }
}

private extension UITouch {
    var localTouch: LocalTouch {
        LocalTouch(
            timestamp: timestamp,
            location: location(in: view)
        )
    }
}

extension CGPoint: Hashable, Identifiable {
    
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
