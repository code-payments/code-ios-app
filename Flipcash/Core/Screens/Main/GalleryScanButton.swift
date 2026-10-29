//
//  GalleryScanButton.swift
//  Flipcash
//

import PhotosUI
import SwiftUI

/// The Scan tab's gallery entry point: a photo glyph that opens the system picker.
///
/// Meant for a `.topBarTrailing` toolbar item, so the system draws the Liquid Glass
/// circle and places it exactly where the Chat and You tabs place theirs.
///
/// `PhotosPicker` is out of process, so tapping this never prompts for library access.
struct GalleryScanButton: View {

    @Binding var selection: PhotosPickerItem?

    var body: some View {
        PhotosPicker(
            selection: $selection,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Image(systemName: "photo.on.rectangle")
        }
        .accessibilityLabel(Text("Scan a code from a photo"))
    }
}
