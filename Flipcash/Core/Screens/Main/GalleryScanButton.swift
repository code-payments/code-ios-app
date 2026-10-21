//
//  GalleryScanButton.swift
//  Flipcash
//

import Photos
import PhotosUI
import SwiftUI
import FlipcashUI

/// The Scan tab's gallery entry point: a photo glyph that opens the system picker.
///
/// Meant for a `.topBarTrailing` toolbar item, so the system draws the Liquid Glass
/// circle and places it exactly where the Chat and You tabs place theirs.
///
/// `PhotosPicker` is out of process, so tapping this never prompts for anything. Only the
/// recent-photo thumbnail needs library access, which is why it is drawn when access
/// happens to exist and never asked for — see ``GalleryThumbnail``.
struct GalleryScanButton: View {

    /// Roughly the footprint of a toolbar symbol, so the thumbnail sits in the glass
    /// circle like a glyph would.
    private static let thumbnailSize: CGFloat = 30

    @Binding var selection: PhotosPickerItem?

    @State private var thumbnail: GalleryThumbnail = GalleryThumbnail()

    var body: some View {
        PhotosPicker(
            selection: $selection,
            matching: .images,
            photoLibrary: .shared()
        ) {
            if let image = thumbnail.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                    .clipShape(Circle())
            } else {
                Image(systemName: "photo.on.rectangle")
            }
        }
        .accessibilityLabel(Text("Scan a code from a photo"))
        .task {
            await thumbnail.loadIfAlreadyAuthorized()
        }
    }
}

/// The most recent photo in the library, when the app can already see the library.
///
/// It never asks. `PHPhotoLibrary.requestAuthorization` would be a permission prompt to
/// decorate an icon, and on a limited-access grant the "most recent photo" is the most
/// recent of an arbitrary subset, which is worse than no thumbnail at all. So: draw it for
/// users who granted access for a profile photo or a group icon, draw the glyph for
/// everyone else.
@Observable
final class GalleryThumbnail {

    private(set) var image: UIImage?

    /// Loads the newest photo, or returns having done nothing if the app has no read grant.
    func loadIfAlreadyAuthorized() async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            return
        }

        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject else {
            return
        }

        let requestOptions = PHImageRequestOptions()
        requestOptions.isNetworkAccessAllowed = false
        requestOptions.deliveryMode = .opportunistic

        let size = CGSize(width: 96, height: 96)

        image = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, _ in
                // `.opportunistic` calls back more than once; only the first matters here.
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
