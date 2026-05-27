//
//  ContactAvatarView.swift
//  FlipcashUI
//

import SwiftUI
import UIKit

/// Circular avatar for a contact. Renders a cached image when supplied;
/// otherwise falls back to a monogram chip built from the display name's
/// initials. Decoded `UIImage`s live in a process-wide `NSCache` keyed by
/// `id`, so scrolling a list of avatars decodes each contact's blob at
/// most once.
public struct ContactAvatarView: View {

    public let id: String
    public let displayName: String
    public let imageData: Data?
    public let size: CGFloat

    public init(id: String, displayName: String, imageData: Data? = nil, size: CGFloat = 44) {
        self.id = id
        self.displayName = displayName
        self.imageData = imageData
        self.size = size
    }

    public var body: some View {
        Group {
            if let imageData,
               let uiImage = ContactAvatarCache.shared.image(forKey: id, data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.25, green: 0.25, blue: 0.25), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.13, green: 0.13, blue: 0.13), location: 1.00),
                    ],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
                .overlay {
                    Text(Self.initials(for: displayName))
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(displayName.isEmpty ? "Contact" : displayName))
        .accessibilityAddTraits(.isImage)
    }

    /// Two-letter monogram for a display name. Two-word names yield the first
    /// letter of the first and last words; single-word names yield the first
    /// two characters; an empty or whitespace-only name yields `"?"`.
    nonisolated public static func initials(for displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }

        let words = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        if words.count >= 2 {
            let first = words.first?.first.map(String.init) ?? ""
            let last = words.last?.first.map(String.init) ?? ""
            return (first + last).uppercased()
        }
        return String(words[0].prefix(2)).uppercased()
    }
}

/// Process-wide cache of decoded contact thumbnails. `NSCache` is thread-safe
/// so the same instance is read from main and background callers without
/// additional synchronization. `countLimit` caps memory growth on devices
/// with very large address books.
nonisolated public final class ContactAvatarCache: @unchecked Sendable {

    public static let shared = ContactAvatarCache()

    private let cache = NSCache<NSString, UIImage>()

    public init(countLimit: Int = 200) {
        cache.countLimit = countLimit
    }

    /// Returns the cached `UIImage` for `key`. Decodes `data` and caches the
    /// result on a miss; returns `nil` when `data` doesn't yield a valid
    /// image.
    public func image(forKey key: String, data: Data) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}

#Preview("Initials — two names") {
    ContactAvatarView(id: "p1", displayName: "Jane Doe")
        .padding()
        .background(Color.backgroundMain)
}

#Preview("Initials — single name") {
    ContactAvatarView(id: "p2", displayName: "Madonna")
        .padding()
        .background(Color.backgroundMain)
}

#Preview("Initials — empty") {
    ContactAvatarView(id: "p3", displayName: "   ")
        .padding()
        .background(Color.backgroundMain)
}
