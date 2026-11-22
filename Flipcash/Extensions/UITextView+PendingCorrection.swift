//
//  UITextView+PendingCorrection.swift
//  Flipcash
//

import UIKit

extension UITextView {
    /// Applies the correction the keyboard is still holding for the word at the cursor, so `text`
    /// includes it.
    ///
    /// The keyboard commits a correction when the word ends. Reporting a selection change ends it
    /// now, without moving the cursor or resigning focus.
    func acceptPendingCorrection() {
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }
}

extension UIApplication {
    /// The text view that is first responder in the key window, or `nil` when no text view has focus.
    var focusedTextView: UITextView? {
        currentKeyWindow?.firstResponderTextView
    }
}

private extension UIView {
    var firstResponderTextView: UITextView? {
        if let textView = self as? UITextView, textView.isFirstResponder { return textView }
        for subview in subviews {
            if let found = subview.firstResponderTextView { return found }
        }
        return nil
    }
}
