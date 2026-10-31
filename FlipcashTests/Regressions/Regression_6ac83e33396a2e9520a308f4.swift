//
//  Regression_6ac83e33396a2e9520a308f4.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import SwiftUI
@testable import Flipcash

/// iOS 18's SwiftUI trapped in `NSRange(_:in:)` while applying the composer's selection, because
/// the selection was handed back after the draft it was taken against had changed underneath it.
/// The hosted cases trap only on iOS 18; the model cases fail on any OS.
@MainActor
@Suite("Regression: 6ac83e3 – composer selection applied to text it didn't belong to", .bug("6ac83e33396a2e9520a308f4"))
struct Regression_6ac83e33396a2e9520a308f4 {

    private static let longDraft = "hi 👋🏽 there 👨‍👩‍👧 ok and some more text"

    // MARK: - Model

    @Test("A selection taken against an earlier draft is withheld from the field")
    func staleSelectionWithheld() {
        let composer = ComposerModel()
        composer.draft = Self.longDraft
        composer.selection = TextSelection(insertionPoint: composer.draft.endIndex)

        composer.draft = "hi"

        #expect(composer.fieldSelection == nil)
        #expect(composer.selection != nil)
    }

    @Test("A selection taken against the current draft reaches the field")
    func currentSelectionPassedThrough() {
        let composer = ComposerModel()
        composer.draft = Self.longDraft
        let selection = TextSelection(insertionPoint: composer.draft.endIndex)

        composer.fieldSelection = selection

        #expect(composer.fieldSelection == selection)
    }

    @Test("The cursor a picked mention places reaches the field")
    func mentionCursorPassedThrough() throws {
        let composer = ComposerModel()
        composer.draft = "hey 👋🏽 @br"
        composer.selection = TextSelection(insertionPoint: composer.draft.endIndex)

        composer.insertMention(username: "brandon")

        #expect(composer.draft == "hey 👋🏽 @brandon ")
        let selection = try #require(composer.fieldSelection)
        #expect(selection == composer.selection)
    }

    // MARK: - Hosted field

    @Test("Shortening the draft under a focused cursor does not trap")
    func shortenedUnderFocusedCursor() async throws {
        let composer = ComposerModel()
        composer.draft = Self.longDraft
        let (window, textView) = try await Self.host(composer)
        defer { window.isHidden = true }
        composer.selection = TextSelection(insertionPoint: composer.draft.endIndex)
        try await Self.settle(window)

        composer.draft = "hi"
        try await Self.settle(window)

        #expect(textView.text == "hi")
    }

    @Test("Shortening the draft after a blur kept the field's cursor does not trap")
    func shortenedAfterBlur() async throws {
        let composer = ComposerModel()
        composer.draft = Self.longDraft
        let (window, textView) = try await Self.host(composer)
        defer { window.isHidden = true }
        composer.selection = TextSelection(insertionPoint: composer.draft.endIndex)
        try await Self.settle(window)
        textView.resignFirstResponder()
        try await Self.settle(window)
        #expect(composer.selection != nil)

        composer.draft = "x"
        try await Self.settle(window)
        textView.becomeFirstResponder()
        try await Self.settle(window)

        #expect(textView.text == "x")
    }

    @Test("Typing mid-text leaves the cursor after the typed character")
    func typingMidTextKeepsCursor() async throws {
        let composer = ComposerModel()
        composer.draft = Self.longDraft
        let (window, textView) = try await Self.host(composer)
        defer { window.isHidden = true }
        textView.selectedRange = NSRange(location: 3, length: 0)
        try await Self.settle(window)

        textView.insertText("x")
        try await Self.settle(window)

        #expect(composer.draft.hasPrefix("hi x👋🏽"))
        #expect(textView.selectedRange == NSRange(location: 4, length: 0))
    }

    /// The composer's field, bound the way `ConversationBottomBar` binds it.
    private struct Field: View {
        @Bindable var composer: ComposerModel

        var body: some View {
            TextField("Message", text: $composer.draft, selection: $composer.fieldSelection, axis: .vertical)
        }
    }

    /// Mounts the field in a window and focuses its text view.
    private static func host(_ composer: ComposerModel) async throws -> (UIWindow, UITextView) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 200)
        window.rootViewController = UIHostingController(rootView: Field(composer: composer))
        window.makeKeyAndVisible()
        try await settle(window)
        let textView = try #require(textView(in: window))
        textView.becomeFirstResponder()
        try await settle(window)
        return (window, textView)
    }

    /// Lets SwiftUI run the updates that apply the field's text and selection.
    private static func settle(_ window: UIWindow) async throws {
        for _ in 0..<5 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func textView(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        return view.subviews.lazy.compactMap(textView(in:)).first
    }
}
