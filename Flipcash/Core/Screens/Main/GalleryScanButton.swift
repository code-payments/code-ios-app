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
/// A Liquid Glass circle the height of the tab bar, so the two read as one row of
/// controls — ``ScanScreen`` lines its leading edge up with the bar's.
///
/// `PhotosPicker` is out of process, so tapping this never prompts for anything. Only the
/// recent-photo thumbnail needs library access, which is why it is drawn when access
/// happens to exist and never asked for — see ``GalleryThumbnail``.
struct GalleryScanButton: View {

    /// Matches `HomeTabBar.iconSize`, so the glyph reads as the same weight of control as a
    /// tab icon.
    private static let glyphSize: CGFloat = 32

    /// The glass circle, sized to the tab bar's capsule so the two sit on one line.
    static var surfaceSize: CGFloat { HomeTabBar.height }

    @Binding var selection: PhotosPickerItem?

    @State private var thumbnail: GalleryThumbnail = GalleryThumbnail()

    var body: some View {
        PhotosPicker(
            selection: $selection,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Group {
                if let image = thumbnail.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.glyphSize, height: Self.glyphSize)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: Self.glyphSize, height: Self.glyphSize)
                }
            }
            .frame(width: Self.surfaceSize, height: Self.surfaceSize)
            .contentShape(Circle())
        }
        .capsuleGlassBackground()
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
