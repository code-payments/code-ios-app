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

public struct CameraPreviewView: View, UIViewRepresentable {
    
    private let session: AnyCameraSession
    
    public init(session: AnyCameraSession) {
        self.session = session
    }
    
    public func makeUIView(context: Context) -> _CameraPreviewView {
        let view = _CameraPreviewView.shared
        updateUIView(view, context: context)
        return view
    }
    
    public func updateUIView(_ uiView: _CameraPreviewView, context: Context) {
        uiView.session = session
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
    
    private let previewLayer = AVCaptureVideoPreviewLayer()
    
    // MARK: - Init -

    required init?(coder: NSCoder) { fatalError() }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        previewLayer.bounds   = bounds
        previewLayer.position = CGPoint(
            x: bounds.width  * 0.5,
            y: bounds.height * 0.5
        )
    }
}

#endif
