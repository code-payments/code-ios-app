//
//  TextView.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import UIKit


/// A SwiftUI view that wraps a UITextView, providing a TextEditor-like experience with placeholder and focus support.
struct TextView: UIViewRepresentable {
    
    @Binding var text: String
    @Binding var isFocused: Bool
    
    let placeholder: String
    let placeholderColor: UIColor
    let font: UIFont
    let textColor: UIColor
    let isEditable: Bool
    let isSelectable: Bool
    let autocapitalizationType: UITextAutocapitalizationType
    let autocorrectionType: UITextAutocorrectionType
    let keyboardType: UIKeyboardType
    
    /// Initializes the TextView with customizable properties.
    /// - Parameters:
    ///   - text: Binding to the text content.
    ///   - isFocused: Binding to the focus state.
    ///   - placeholder: Placeholder text to display when the text is empty.
    ///   - placeholderColor: Color of the placeholder text.
    ///   - font: Font for the text view.
    ///   - textColor: Color of the input text.
    ///   - isEditable: Whether the text view is editable.
    ///   - isSelectable: Whether the text view is selectable.
    ///   - autocapitalizationType: Autocapitalization behavior.
    ///   - autocorrectionType: Autocorrection behavior.
    ///   - keyboardType: Keyboard type for input.
    init(
        text: Binding<String>,
        isFocused: Binding<Bool> = .constant(false), // Default to non-focused
        placeholder: String = "",
        placeholderColor: UIColor = .placeholderText,
        font: UIFont = .preferredFont(forTextStyle: .body),
        textColor: UIColor = .label,
        isEditable: Bool = true,
        isSelectable: Bool = true,
        autocapitalizationType: UITextAutocapitalizationType = .sentences,
        autocorrectionType: UITextAutocorrectionType = .default,
        keyboardType: UIKeyboardType = .default
    ) {
        self._text = text
        self._isFocused = isFocused
        self.placeholder = placeholder
        self.placeholderColor = placeholderColor
        self.font = font
        self.textColor = textColor
        self.isEditable = isEditable
        self.isSelectable = isSelectable
        self.autocapitalizationType = autocapitalizationType
        self.autocorrectionType = autocorrectionType
        self.keyboardType = keyboardType
    }
    
    // MARK: - UIViewRepresentable
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
//        textView.translatesAutoresizingMaskIntoConstraints = false // Use Auto Layout
        textView.delegate = context.coordinator
        textView.isScrollEnabled = true
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.font = font
        textView.textColor = textColor
        textView.autocapitalizationType = autocapitalizationType
        textView.autocorrectionType = autocorrectionType
        textView.keyboardType = keyboardType
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4) // Matches TextEditor
        textView.backgroundColor = .clear // Matches TextEditor transparency
        textView.setContentHuggingPriority(.required, for: .vertical)
        
        // Configure initial text or placeholder
        updateTextViewContent(textView, text: text)
        
        // Ensure layout updates for dynamic type
        textView.adjustsFontForContentSizeCategory = true
        
        // Prevent unwanted scrolling behavior
        textView.textContainer.lineFragmentPadding = 0
        
        // Handle keyboard dismissal
        textView.keyboardDismissMode = .interactive
        
        // Ensure proper accessibility
        textView.isAccessibilityElement = true
        textView.accessibilityLabel = placeholder.isEmpty ? "Text input" : placeholder
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Update text and placeholder
        updateTextViewContent(uiView, text: text)
        
        // Update configuration
        uiView.isEditable = isEditable
        uiView.isSelectable = isSelectable
        uiView.font = font
        uiView.textColor = textColor
        uiView.autocapitalizationType = autocapitalizationType
        uiView.autocorrectionType = autocorrectionType
        uiView.keyboardType = keyboardType
        
        // Handle focus state
        if isFocused && !uiView.isFirstResponder && isEditable {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        
        // Ensure cursor remains visible
        if uiView.isFirstResponder {
            uiView.scrollRangeToVisible(uiView.selectedRange)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Helper Methods
    
    private func updateTextViewContent(_ textView: UITextView, text: String) {
        if text.isEmpty && !placeholder.isEmpty {
            textView.text = placeholder
            textView.textColor = placeholderColor
            textView.accessibilityValue = ""
        } else {
            textView.text = text
            textView.textColor = textColor
            textView.accessibilityValue = text
        }
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextView
        
        init(_ parent: TextView) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            // Only update binding if the text is not the placeholder
            if textView.textColor != parent.placeholderColor {
                parent.text = textView.text
            }
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            // Clear placeholder when editing begins
            if textView.textColor == parent.placeholderColor {
                textView.text = ""
                textView.textColor = parent.textColor
            }
            // Update focus state
            if !parent.isFocused {
                DispatchQueue.main.async {
                    self.parent.isFocused = true
                }
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            // Restore placeholder if text is empty
            if textView.text.isEmpty && !parent.placeholder.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = parent.placeholderColor
                textView.accessibilityValue = ""
            }
            // Update focus state
            if parent.isFocused {
                DispatchQueue.main.async {
                    self.parent.isFocused = false
                }
            }
        }
        
        // Handle dynamic type changes
        func textViewDidChangeSelection(_ textView: UITextView) {
            // Ensure cursor is visible
            textView.scrollRangeToVisible(textView.selectedRange)
        }
        
        // Prevent pasting placeholder text
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let currentText = textView.text as NSString
            let newText = currentText.replacingCharacters(in: range, with: text)
            
            // Clear placeholder if user types and text was placeholder
            if textView.textColor == parent.placeholderColor && !text.isEmpty {
                textView.text = ""
                textView.textColor = parent.textColor
            }
            
            return true
        }
    }
}
