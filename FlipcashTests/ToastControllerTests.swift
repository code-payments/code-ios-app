//
//  ToastControllerTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashUI

@MainActor
@Suite("Toast controller")
struct ToastControllerTests {

    @Test("A new toast replaces the one showing")
    func replaces() {
        let toasts = ToastController()
        toasts.show(.init("First"))
        toasts.show(.init("Second"))

        #expect(toasts.current?.message == "Second")
    }

    @Test("Covering the host dismisses the toast showing")
    func coverDismisses() {
        let toasts = ToastController()
        toasts.show(.init("Chat archived"))

        toasts.isCovered = true

        #expect(toasts.current == nil)
    }

    @Test("A toast shown while covered is dropped, and uncovering does not bring it back")
    func coveredDrops() {
        let toasts = ToastController()
        toasts.isCovered = true
        toasts.show(.init("Chat archived"))
        #expect(toasts.current == nil)

        toasts.isCovered = false

        #expect(toasts.current == nil)
    }

    @Test("An in-place toast keeps the slot of the one showing, so the entrance does not replay")
    func inPlaceKeepsSlot() throws {
        let toasts = ToastController()
        toasts.show(.init("3 steps"), inPlace: true)
        let first = try #require(toasts.current)

        toasts.show(.init("2 steps"), inPlace: true)
        let second = try #require(toasts.current)

        #expect(second.message == "2 steps")
        #expect(second.slot == first.slot)
        #expect(second.id != first.id)
    }

    @Test("A toast not shown in place takes a new slot")
    func replacementTakesNewSlot() throws {
        let toasts = ToastController()
        toasts.show(.init("First"))
        let first = try #require(toasts.current)

        toasts.show(.init("Second"))

        #expect(toasts.current?.slot != first.slot)
    }

    @Test("Dismissing a replaced toast leaves the current one up")
    func staleDismissIgnored() throws {
        let toasts = ToastController()
        toasts.show(.init("First"))
        let first = try #require(toasts.current)
        toasts.show(.init("Second"))

        toasts.dismiss(first.id)

        #expect(toasts.current?.message == "Second")
    }
}
