//
//  UIAccessibility+TestSupport.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Darwin
import UIKit

extension UIAccessibility {

    /// Turns on the test host's accessibility runtime, so hosted views expose their accessibility elements.
    static func enableForHostedTests() {
        _ = AutomationSwitch.turnedOn
    }

    /// Whether the test host's accessibility runtime is on, worded for a hosted spec's timeout message.
    static var hostedTestsState: String {
        switch AutomationSwitch.isOn {
        case true?: "accessibility on"
        case false?: "accessibility off"
        case nil: "no accessibility switch"
        }
    }
}

/// libAccessibility's automation switch, which XCUITest turns on in the app it drives.
private enum AutomationSwitch {
    private typealias Read = @convention(c) () -> Int32
    private typealias Write = @convention(c) (Int32) -> Void

    static var isOn: Bool? {
        read.map { $0() != 0 }
    }

    static let turnedOn: Bool = {
        guard let read, let write else { return false }
        if read() == 0 {
            write(1)
            // The switch is the simulator's, not the process's, so the run turns it back off.
            atexit { AutomationSwitch.write?(0) }
        }
        return read() != 0
    }()

    private static var read: Read? { symbol("_AXSAutomationEnabled") }
    private static var write: Write? { symbol("_AXSSetAutomationEnabled") }

    private static func symbol<T>(_ name: String) -> T? {
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let pointer = dlsym(library, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
