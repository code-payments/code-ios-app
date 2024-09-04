//
//  PhotoPickerView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import Photos
import PhotosUI

public struct PickerView: UIViewControllerRepresentable {
    
    public var selection: (UIImage) -> Void
    
    public init(selection: @escaping (UIImage) -> Void) {
        self.selection = selection
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(selection: selection)
    }
    
    public func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        
        return picker
    }
    
    public func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
}

// MARK: - Coordinator -

extension PickerView {
    public class Coordinator: NSObject, PHPickerViewControllerDelegate {
        
        private var selection: (UIImage) -> Void
        
        init(selection: @escaping (UIImage) -> Void) {
            self.selection = selection
        }
        
        public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else {
                return
            }
            
            let didSelect = selection
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { item, error in
                    guard let image = item as? UIImage else {
                        return
                    }
                    
                    DispatchQueue.main.async {
                        didSelect(image)
                    }
                }
            }
        }
    }
}
