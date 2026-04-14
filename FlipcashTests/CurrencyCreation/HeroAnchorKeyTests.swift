//
//  HeroAnchorKeyTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
@testable import Flipcash

@Suite("HeroAnchorKey")
struct HeroAnchorKeyTests {

    @Test("Default value is empty")
    func defaultValueIsEmpty() {
        #expect(HeroAnchorKey.defaultValue.isEmpty)
    }

    @Test("Merge is last-writer-wins per key")
    func mergeLastWriterWinsPerKey() {
        var current: [HeroAnchorID: Int] = [.circle: 1]
        let incoming: [HeroAnchorID: Int] = [.circle: 2, .name: 9]
        current.merge(incoming) { _, new in new }

        #expect(current[.circle] == 2)
        #expect(current[.name] == 9)
    }
}
