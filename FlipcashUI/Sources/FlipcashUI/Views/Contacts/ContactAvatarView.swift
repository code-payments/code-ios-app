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
                LinearGradient.avatarPlaceholder
                    .overlay {
                        switch Self.monogram(for: displayName) {
                        case .initials(let text):
                            Text(text)
                                // Scales with the avatar, preserving the default (44pt) avatar's
                                // 16pt monogram proportions at any size.
                                .font(.default(size: size * 16 / 44, weight: .bold))
                                .foregroundStyle(Color.textMain)
                        case .placeholder:
                            PeopleSilhouette(size: size)
                        }
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(displayName.isEmpty ? "Contact" : displayName))
        .accessibilityAddTraits(.isImage)
    }

    /// The avatar's text content: letter initials drawn from the display name,
    /// or `.placeholder` when there are none — in which case the avatar shows a
    /// generic person glyph instead of an unreadable monogram.
    nonisolated public enum Monogram: Equatable, Sendable {
        case initials(String)
        case placeholder
    }

    /// A two-letter monogram, considering only words that begin with a letter:
    /// two such words yield the first letter of the first and last; a single
    /// word yields its first two characters. A name with no letter-leading
    /// words (e.g. a bare phone number) yields `.placeholder`.
    nonisolated public static func monogram(for displayName: String) -> Monogram {
        let words = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .filter { $0.first?.isLetter == true }
        guard let first = words.first else { return .placeholder }
        if words.count >= 2, let last = words.last {
            let initials = String(first.prefix(1)) + String(last.prefix(1))
            return .initials(initials.uppercased())
        }
        return .initials(String(first.prefix(2)).uppercased())
    }
}

/// Process-wide cache of decoded contact thumbnails. `NSCache` is thread-safe
/// so the same instance is read from main and background callers without
/// additional synchronization. `countLimit` caps memory growth on devices
/// with very large address books.
nonisolated public final class ContactAvatarCache: @unchecked Sendable {

    public static let shared = ContactAvatarCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
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

/// The shared "people" silhouette glyph. The avatar placeholder and the
/// stacked-people footer icon both render this over `LinearGradient.avatarPlaceholder`.
/// Fills its circular container from the bottom (like a portrait) and blends
/// subtly into the gradient. Expects a square container (an avatar circle's
/// `.overlay`), which `scaledToFill` fills; `size` only scales the top inset.
public struct PeopleSilhouette: View {

    public let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Image.asset(.people)
            .resizable()
            .scaledToFill()
            .padding(.top, size * 0.25)
            .foregroundStyle(Color.textMain)
            .blendMode(.overlay)
    }
}

public extension LinearGradient {
    /// The dark vertical gradient behind contact avatar placeholders and the
    /// people glyphs composed from them (e.g. the "Add More Contacts" footer
    /// icon), so both stay in sync.
    static let avatarPlaceholder = LinearGradient(
        stops: [
            Gradient.Stop(color: Color(red: 0.25, green: 0.25, blue: 0.25), location: 0.00),
            Gradient.Stop(color: Color(red: 0.13, green: 0.13, blue: 0.13), location: 1.00),
        ],
        startPoint: UnitPoint(x: 0.5, y: 0),
        endPoint: UnitPoint(x: 0.5, y: 1)
    )
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

#Preview("Placeholder — phone number") {
    ContactAvatarView(id: "p3", displayName: "(586) 980-2333")
        .padding()
        .background(Color.backgroundMain)
}

#Preview("Placeholder — empty") {
    ContactAvatarView(id: "p4", displayName: "   ")
        .padding()
        .background(Color.backgroundMain)
}
