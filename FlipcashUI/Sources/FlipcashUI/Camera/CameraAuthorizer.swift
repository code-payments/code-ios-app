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
    
    public func authorize() async throws -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: Self.mediaType)
        if status != .authorized {
            await AVCaptureDevice.requestAccess(for: Self.mediaType)
            updateStatus()
            return self.status
        } else {
            return status
        }
    }
    
    private func updateStatus() {
        status = AVCaptureDevice.authorizationStatus(for: Self.mediaType)
    }
}
