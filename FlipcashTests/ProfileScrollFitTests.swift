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

    @Test("Content that shrinks to fit stops overflowing")
    func shrinks_to_fit() {
        var fit = ProfileScrollFit()
        fit.update(visibleHeight: 700, contentHeight: 1200)
        #expect(fit.overflows)

        fit.update(visibleHeight: 700, contentHeight: 700)
        #expect(fit.overflows == false)
    }
}
