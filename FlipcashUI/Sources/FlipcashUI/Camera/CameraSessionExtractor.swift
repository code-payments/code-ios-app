//
//  CameraSessionExtractor.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import AVKit

public nonisolated protocol CameraSessionExtractor: AnyObject {

    associatedtype Output

    init()

    func extract(output: AVCaptureOutput, sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) -> Output?
}
