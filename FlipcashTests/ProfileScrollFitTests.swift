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

    @Test("The bottom fade shows only while overflowing content has more below")
    func fade_lifts_at_end() {
        var fit = ProfileScrollFit()
        fit.update(visibleHeight: 700, contentHeight: 1200, isAtEnd: false)
        #expect(fit.fadesBottom)

        fit.update(visibleHeight: 700, contentHeight: 1200, isAtEnd: true)
        #expect(fit.fadesBottom == false)

        fit.update(visibleHeight: 700, contentHeight: 700, isAtEnd: false)
        #expect(fit.fadesBottom == false)
    }
}
