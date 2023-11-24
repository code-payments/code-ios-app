//
//  CustomTextField.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct CustomTextField: UIViewRepresentable {
    
    @Binding var content: String
    @Binding var isActive: Bool
    
    private let configuration: (UITextField) -> Void
    
    public init(content: Binding<String>, isActive: Binding<Bool>, configuration: @escaping (UITextField) -> Void) {
        self._content  = content
        self._isActive = isActive
        self.configuration = configuration
    }
    
    public func makeCoordinator() -> CustomTextFieldCoordinator {
        CustomTextFieldCoordinator(content: $content, isActive: $isActive)
    }
    
    public func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        context.coordinator.setup(for: textField)
        return textField
    }
    
    public func updateUIView(_ textField: UITextField, context: Context) {
        textField.text = content
        textField.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        configuration(textField)
        
        DispatchQueue.main.async {
            if isActive {
                textField.becomeFirstResponder()
            } else {
                _ = textField.resignFirstResponder()
            }
        }
    }
}

// MARK: - CustomTextFieldCoordinator -

public class CustomTextFieldCoordinator: NSObject, UITextFieldDelegate {
    
    @Binding var content: String
    @Binding var isActive: Bool
    
    init(content: Binding<String>, isActive: Binding<Bool>) {
        self._content  = content
        self._isActive = isActive
        
        super.init()
    }
    
    func setup(for textField: UITextField) {
        textField.addTarget(self, action: #selector(editingDidChange(_:)), for: .editingChanged)
        textField.delegate = self
    }
    
    @objc private func editingDidChange(_ textField: UITextField) {
        content = textField.text ?? ""
        textField.text = content
    }
    
    // MARK: - UITextFieldDelegate -
    
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.async {
            if !self.isActive {
                self.isActive = true
            }
        }
    }
    
    public func textFieldDidEndEditing(_ textField: UITextField) {
        DispatchQueue.main.async {
            if self.isActive {
                self.isActive = false
            }
        }
    }
}

#endif
