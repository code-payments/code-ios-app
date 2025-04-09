//
//  CameraAuthorizer.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import AVKit

@MainActor
@Observable
public class CameraAuthorizer {
    
    public var status: AVAuthorizationStatus = .notDetermined
    
    private static let mediaType = AVMediaType.video
    
    // MARK: - Init -
    
    public init() {
        updateStatus()
    }
    
    // MARK: - Authorize -
    
    public func authorize(completion: ((AVAuthorizationStatus) -> Void)? = nil) {
        let status = AVCaptureDevice.authorizationStatus(for: Self.mediaType)
        if status != .authorized {
            Task {
                await AVCaptureDevice.requestAccess(for: Self.mediaType)
                updateStatus()
                completion?(self.status)
            }
        } else {
            completion?(status)
        }
    }
    
    private func updateStatus() {
        status = AVCaptureDevice.authorizationStatus(for: Self.mediaType)
    }
}
