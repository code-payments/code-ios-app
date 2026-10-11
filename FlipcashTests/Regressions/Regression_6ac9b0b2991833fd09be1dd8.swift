//
//  Regression_6ac9b0b2991833fd09be1dd8.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import SwiftUI
import AVFoundation
@testable import Flipcash

/// The attach panel hung on main in `AVCaptureVideoPreviewLayer.setSession:`, because every mount
/// of the camera card built a new preview layer and attached it to the warm session.
@MainActor
@Suite("Regression: 6ac9b0b – camera preview reattached its session on every mount", .bug("6ac9b0b2991833fd09be1dd8"))
struct Regression_6ac9b0b2991833fd09be1dd8 {

    /// Mounts the viewfinder in a window and returns the preview layer it shows.
    private func mountedPreviewLayer(for camera: ChatPhotoCamera) throws -> AVCaptureVideoPreviewLayer {
        let host = UIHostingController(rootView: ChatCameraPreview(camera: camera).frame(width: 200, height: 300))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 200, height: 300)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.view.layoutIfNeeded()
        return try #require(Self.previewLayer(in: host.view.layer))
    }

    private static func previewLayer(in layer: CALayer) -> AVCaptureVideoPreviewLayer? {
        if let preview = layer as? AVCaptureVideoPreviewLayer { return preview }
        return layer.sublayers?.lazy.compactMap(previewLayer(in:)).first
    }

    @Test("Every mount shows the camera's own preview layer instead of building a new one")
    func reusesCameraLayer() throws {
        let camera = ChatPhotoCamera()
        let first = try mountedPreviewLayer(for: camera)
        let second = try mountedPreviewLayer(for: camera)
        #expect(first === camera.previewLayer)
        #expect(second === camera.previewLayer)
        #expect(camera.previewLayer.session === camera.session)
    }
}
