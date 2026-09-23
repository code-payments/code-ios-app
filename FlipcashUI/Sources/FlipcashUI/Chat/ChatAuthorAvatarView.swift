//
//  ChatAuthorAvatarView.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit
import SwiftUI
import FlipcashCore

/// The 24pt circle in the leading gutter of an attributed transcript row, drawn in UIKit. The
/// typing indicator draws larger ones with a person glyph as the fallback.
///
/// Deliberately not a `UIHostingController` around ``ContactAvatarView``: the transcript recycles
/// its cells, and hosting a SwiftUI view per recycled row costs a view-controller adoption on every
/// dequeue. The three-tier fallback is the same one that view uses — decoded bytes, then the
/// BlurHash, then a monogram over the shared placeholder gradient — reading through the same
/// process-wide caches, so an avatar decoded for a contact list is a hit here.
final class ChatAuthorAvatarView: UIView {

    /// Figma sizes the gutter circle at 24pt (nodes 10125:19169-19184).
    static let size: CGFloat = 24

    /// What stands in for a picture the author does not have.
    enum Fallback {
        /// The author's initials, or the bare gradient when the name has none.
        case monogram
        /// A white person glyph, whatever the name.
        case personGlyph
    }

    private let fallback: Fallback
    private let imageView = UIImageView()
    private let monogram = UILabel()
    private let personGlyph = UIImageView(image: UIImage(systemName: "person.fill"))
    private let gradient = CAGradientLayer()

    init(size: CGFloat = ChatAuthorAvatarView.size, fallback: Fallback = .monogram) {
        self.fallback = fallback
        super.init(frame: .zero)

        layer.cornerRadius = size / 2
        layer.masksToBounds = true

        // The same two stops as `LinearGradient.avatarPlaceholder`, so a monogram in the transcript
        // matches one in a contact list.
        gradient.colors = [
            UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1).cgColor,
            UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(gradient)

        // Scales the 44pt avatar's 16pt monogram down to this size, the way `ContactAvatarView` does.
        monogram.font = .default(size: size * 16 / 44, weight: .bold)
        monogram.textColor = UIColor(Color.textMain)
        monogram.textAlignment = .center
        monogram.translatesAutoresizingMaskIntoConstraints = false
        addSubview(monogram)

        personGlyph.tintColor = .white
        personGlyph.contentMode = .scaleAspectFit
        personGlyph.isHidden = true
        personGlyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(personGlyph)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            // Android pads its Person icon 5dp inside the circle.
            personGlyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            personGlyph.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            personGlyph.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            personGlyph.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            monogram.centerXAnchor.constraint(equalTo: centerXAnchor),
            monogram.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The gradient layer is not laid out by Auto Layout, and its implicit resize animation would
        // otherwise drift for a frame when a recycled cell changes size.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    /// Draws `author`, using `imageData` when the bytes have arrived. Safe to call on every
    /// reconfigure — a repeat with the same inputs reads the decoded image straight out of the cache.
    func configure(with author: ChatAuthor, imageData: Data?) {
        let key = author.id.uuidString
        if let imageData, let image = ContactAvatarCache.shared.image(forKey: key, data: imageData) {
            imageView.image = image
        } else {
            imageView.image = BlurHashCache.shared.image(for: author.blurhash)
        }
        switch fallback {
        case .monogram:
            switch ContactAvatarView.monogram(for: author.name) {
            case .initials(let text):
                monogram.text = text
            case .placeholder:
                // No letters to work with — the gradient alone stands in, rather than the people glyph
                // the full-size avatar draws, which is illegible at 24pt.
                monogram.text = nil
            }
        case .personGlyph:
            monogram.text = nil
            personGlyph.isHidden = imageView.image != nil
        }
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = author.name.isEmpty ? "Contact" : author.name
    }

    /// Clears the image so a recycled row never shows the previous author's face.
    func reset() {
        imageView.image = nil
        monogram.text = nil
        personGlyph.isHidden = true
        accessibilityLabel = nil
    }
}
#endif
