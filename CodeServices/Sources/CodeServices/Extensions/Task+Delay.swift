//
//  Task+Delay.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Task where Success == Never, Failure == Never {
    public static func delay(seconds: Int) async throws {
        try await delay(milliseconds: seconds * 1_000)
    }
    
    public static func delay(milliseconds: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }
}
