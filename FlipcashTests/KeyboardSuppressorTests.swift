//
//  KeyboardSuppressorTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import UIKit
@testable import Flipcash

// Serialized: the suppressor observes `NotificationCenter.default`, which is
// process-wide, so a `keyboardWillShow` posted by one test would be counted by
// every other test's suppressor still inside its window.
@Suite("Keyboard Suppressor", .serialized)
@MainActor
struct KeyboardSuppressorTests {

    /// Counts dismissals in place of the real `resignFirstResponder`.
    private final class Counter {
        var count = 0
    }

    private static let window = 150

    private func makeSuppressor() -> (KeyboardSuppressor, Counter) {
        let counter = Counter()
        let suppressor = KeyboardSuppressor(windowMilliseconds: Self.window) { counter.count += 1 }
        return (suppressor, counter)
    }

    private func postKeyboardWillShow() {
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
    }

    @Test("Suppressing lowers the keyboard immediately")
    func lowersOnSuppress() {
        let (suppressor, counter) = makeSuppressor()
        suppressor.suppress()
        #expect(counter.count == 1)
    }

    @Test("A keyboard raised inside the window is lowered again")
    func lowersRestoreInsideWindow() {
        let (suppressor, counter) = makeSuppressor()
        suppressor.suppress()
        postKeyboardWillShow()
        #expect(counter.count == 2)
    }

    @Test("A keyboard raised after the window is left alone")
    func ignoresRaiseAfterWindow() async throws {
        let (suppressor, counter) = makeSuppressor()
        suppressor.suppress()
        try await Task.sleep(for: .milliseconds(Self.window * 3))
        postKeyboardWillShow()
        #expect(counter.count == 1)
    }

    @Test("Re-entering does not extend the window")
    func reentryDoesNotExtendWindow() async throws {
        let (suppressor, counter) = makeSuppressor()
        suppressor.suppress()
        // The scanner re-enters the tip flow on every decoded frame; each
        // re-entry lowers, but the bar still lifts on the original deadline.
        suppressor.suppress()
        #expect(counter.count == 2)

        try await Task.sleep(for: .milliseconds(Self.window * 3))
        postKeyboardWillShow()
        #expect(counter.count == 2)
    }
}
