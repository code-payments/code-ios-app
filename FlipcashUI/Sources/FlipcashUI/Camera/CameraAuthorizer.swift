//
//  CameraAuthorizer.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import AVKit

@MainActor
public class CameraAuthorizer: ObservableObject {
    
    @Published public var status: AVAuthorizationStatus = .notDetermined
    
    private let mediaType = AVMediaType.video
    
    // MARK: - Init -
    
    public init() {
        updateStatus()
    }
    
    // MARK: - Authorize -
    
    public func authorize(completion: ((AVAuthorizationStatus) -> Void)? = nil) {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        if status != .authorized {
            AVCaptureDevice.requestAccess(for: mediaType) { requested in
                Task { @MainActor in
                    self.updateStatus()
                    completion?(self.status)
                }
            }
        } else {
            completion?(status)
        }
    }
    
    private func updateStatus() {
        status = AVCaptureDevice.authorizationStatus(for: mediaType)
    }
}
