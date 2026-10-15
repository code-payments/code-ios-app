//
//  JumpToBottomColumnTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import Testing
import UIKit
import FlipcashCore
@testable import Flipcash
@testable import FlipcashUI

/// The jump-to-bottom column's place over the bar's trailing control.
@MainActor
@Suite("Jump to bottom column")
struct JumpToBottomColumnTests {

    @Test("The trailing control's centre inset is the control inset plus half its height")
    func trailingControlCentreInset_values() {
        // The composing column is asserted on the function: the spring that carries the view there
        // does not advance in a test host with no display.
        #expect(BarMetrics.trailingControlCentreInset(isCompact: true) == BarMetrics.compactInset + BarMetrics.contentHeight / 2)
        #expect(BarMetrics.trailingControlCentreInset(isCompact: false) == BarMetrics.edgeInset + BarMetrics.contentHeight / 2)
    }
}
