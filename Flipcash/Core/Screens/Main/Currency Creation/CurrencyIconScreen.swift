//
//  CurrencyIconScreen.swift
//  Flipcash
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashUI

struct CurrencyIconScreen: View {
    let currencyName: String
    @Binding var selectedImage: UIImage?
    let namespace: Namespace.ID
    let onContinue: () -> Void

    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Text("Upload Currency Icon")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                Text("Choose an image that represents your currency. It will be displayed as a circular icon.")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                Spacer()

                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") {
                        isShowingPhotoPicker = true
                    }
                    Button("Choose File", systemImage: "folder") {
                        isShowingFilePicker = true
                    }
                } label: {
                    UploadCircle(selectedImage: selectedImage)
                        .contentTransition(.identity)
                }
                .menuIndicator(.hidden)

                Text(currencyName)
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 16)

                Spacer()

                Text("500x500 Recommended")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 12)

                Button("Next", action: onContinue)
                    .buttonStyle(.filled)
                    .disabled(selectedImage == nil)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
        .fullScreenCover(isPresented: $isShowingPhotoPicker) {
            ImagePickerWithEditor { image in
                Task.detached {
                    let compressed = ImageCompressor.compress(image)
                    await MainActor.run { selectedImage = compressed }
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first,
                      url.startAccessingSecurityScopedResource() else { return }

                let data = try? Data(contentsOf: url)
                url.stopAccessingSecurityScopedResource()

                guard let data, let image = UIImage(data: data) else { return }

                Task.detached {
                    let compressed = ImageCompressor.compress(image)
                    await MainActor.run { selectedImage = compressed }
                }

            case .failure:
                break
            }
        }
    }

}

// MARK: - ImagePickerWithEditor

/// Wraps `UIImagePickerController` with `allowsEditing = true` to provide
/// the native crop/zoom interface before returning the image.
private struct ImagePickerWithEditor: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            picker.dismiss(animated: true)
            if let image {
                onImagePicked(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - UploadCircle

private struct UploadCircle: View {
    let selectedImage: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.2))

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(width: 150, height: 150)
        .clipShape(Circle())
    }
}
