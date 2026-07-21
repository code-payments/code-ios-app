//
//  ImagePickerWithEditor.swift
//  Flipcash
//

import SwiftUI

/// Presents the system photo library and returns the user's square-cropped
/// selection.
struct ImagePickerWithEditor: UIViewControllerRepresentable {

    let onImagePicked: (UIImage) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        // PhotosPicker has no crop editor; allowsEditing is why this stays on
        // UIImagePickerController.
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        let onImagePicked: (UIImage) -> Void
        let onDismiss: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onDismiss: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onDismiss = onDismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let image { onImagePicked(image) }
            onDismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDismiss()
        }
    }
}
