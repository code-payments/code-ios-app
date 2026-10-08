//
//  ProfileScrollFitTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash

@MainActor
@Suite("ProfileScrollFit")
struct ProfileScrollFitTests {

    @Test("Content shorter than the screen doesn't overflow")
    func short_fits() {
        var fit = ProfileScrollFit()
        fit.update(visibleHeight: 700, contentHeight: 700)
        #expect(fit.overflows == false)
        #expect(fit.visibleHeight == 700)
    }

    @Test("Content taller than the screen overflows")
    func tall_overflows() {
        var fit = ProfileScrollFit()
        fit.update(visibleHeight: 700, contentHeight: 1200)
        #expect(fit.overflows)
    }

    @Test("Content that shrinks to fit releases the clearance it turned on")
    func clearance_releases() {
        var fit = ProfileScrollFit()
        fit.update(visibleHeight: 700, contentHeight: 1200)
        #expect(fit.overflows)

        // The 56pt clearance leaves 644 visible; 690 overflows that but fits the 700 the screen
        // has without it.
        fit.update(visibleHeight: 644, contentHeight: 690)
        #expect(fit.overflows == false)
    }

    @Test("Overflowing content stays overflowing once the clearance is on")
    func clearance_holds() {
        var fit = ProfileScrollFit()
        fit.update(visibleHeight: 700, contentHeight: 1200)
        fit.update(visibleHeight: 644, contentHeight: 1200)
        #expect(fit.overflows)
    }
}
