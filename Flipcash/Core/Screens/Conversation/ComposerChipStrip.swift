//
//  ComposerChipStrip.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI

/// What a staged chip draws over its thumbnail.
enum ComposerChipBadge: Equatable {
    /// The upload failed and can be tried again.
    case retry
    /// The server refused the photo; the only way forward is to remove it.
    case error
    /// The thumbnail stands alone: uploaded, or uploading quietly until the send, whose bubble
    /// shows the progress.
    case none

    /// Returns the badge for a chip in `state`.
    init(_ state: ComposerChip.State) {
        switch state {
        case .preparing, .uploading, .uploaded:
            self = .none
        case .failed(.retryable):           self = .retry
        case .failed(.notRetryable):        self = .error
        }
    }
}

/// The photos staged for the next send, as a row of thumbnails inside the message field, above its text.
///
/// Part of the bar's own content rather than a reveal like the reply strip: its arrival changes the
/// bar's height the way a draft wrapping to a second line does, which the screen takes in one frame.
struct ComposerChipStrip: View {

    /// Side of a chip's square thumbnail, per the spec's 56pt chips.
    static let chipSize: CGFloat = 56

    let chips: [ComposerChip]
    /// The chip the attach surface is shrinking onto, held hidden until it has.
    var landingChipID: ComposerChip.ID? = nil
    /// Receives the landing chip's frame in window coordinates once it is laid out.
    var onLandingChipFrame: (CGRect) -> Void = { _ in }
    let onRemove: (ComposerChip.ID) -> Void
    let onRetry: (ComposerChip) -> Void
    /// How far the first and last chips sit in from the strip's edges, where the chips scrolling
    /// past fade out instead of being cut off.
    var edgeInset: CGFloat = 0

    /// Returns whether the strip is drawn: while chips are staged, and not during an edit, which
    /// takes the bar for itself and hands the chips back when it ends.
    static func isShown(chipCount: Int, isEditing: Bool) -> Bool {
        chipCount > 0 && !isEditing
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let motion = AttachMotion(reduceMotion: reduceMotion)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let isLanding = chip.id == landingChipID
                    ComposerChipView(
                        chip: chip,
                        onRemove: { onRemove(chip.id) },
                        onRetry: { onRetry(chip) }
                    )
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                        if isLanding {
                            onLandingChipFrame(frame)
                        }
                    }
                    .opacity(isLanding ? 0 : 1)
                    .animation(ChatMotion.attachContentIn, value: isLanding)
                    // Arrives where it lies, so the frame it reports is where the card lands.
                    .transition(motion.chipTransition(isLanding: isLanding))
                }
            }
            // A chip arriving or leaving slides its neighbours over on the chip spring, unless the
            // change came with an animation of its own.
            .transaction(value: chips.map(\.id)) { transaction in
                if transaction.animation == nil, !transaction.disablesAnimations {
                    transaction.animation = ChatMotion.composerChip.animation
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, edgeInset, for: .scrollContent)
        .frame(height: Self.chipSize)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: edgeInset)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: edgeInset)
            }
        }
        .accessibilityIdentifier("composer-chip-strip")
    }
}

/// One staged photo: its thumbnail, a remove button, and the upload's badge.
private struct ComposerChipView: View {

    let chip: ComposerChip
    let onRemove: () -> Void
    let onRetry: () -> Void

    private static let cornerRadius: CGFloat = 10

    /// A thumbnail sized for the chip, decoded off the main thread. The staged image is the full
    /// camera or library photo, which is far too large to redraw at 56pt on every pass.
    @State private var thumbnail: UIImage?

    var body: some View {
        let size = ComposerChipStrip.chipSize
        // Sized by the colour alone: a filled photo reports its own aspect's height, and laid out
        // beside the colour it stretched the chip past its square and over the row below.
        Color.backgroundSecondary
            .overlay {
                // The capture's preview until the thumbnail is decoded, so a chip shrinking out of the
                // camera has its photo from the first frame.
                if let image = thumbnail ?? chip.preview {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay { badge }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            ComposerChipRemoveButton(label: "Remove photo", identifier: "composer-chip-remove", action: onRemove)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer-chip")
        .task(id: chip.id) {
            let scale = UITraitCollection.current.displayScale
            let pixels = CGSize(width: size * scale, height: size * scale)
            thumbnail = await chip.image.byPreparingThumbnail(ofSize: pixels) ?? chip.image
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch ComposerChipBadge(chip.state) {
        case .retry:
            Button(action: onRetry) {
                ZStack {
                    Color.black.opacity(0.45)
                    Image.icon(.arrowRotateClockwise)
                        .iconSize(22)
                        .foregroundStyle(Color.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry photo upload")
            .accessibilityIdentifier("composer-chip-retry")
        case .error:
            ZStack {
                Color.black.opacity(0.45)
                Image.icon(.exclamationTriangle)
                    .iconSize(22)
                    .foregroundStyle(Color.textError)
            }
            .accessibilityLabel("Photo can't be sent")
        case .none:
            EmptyView()
        }
    }
}

/// The draft link's preview as the recipient will see it: a compact card with the page's image,
/// host, description and title, a spinner while it loads, and a remove button on its corner.
struct ComposerLinkChip: View {

    let preview: ComposerLinkPreview
    let onRemove: () -> Void

    private static let cardCornerRadius: CGFloat = 14
    private static let imageCornerRadius: CGFloat = 8
    private static let imageSize: CGFloat = 44
    private static let maxCardWidth: CGFloat = 280

    /// How far the remove button hangs past the card's top-trailing corner.
    private static let removeOverhang: CGFloat = 9

    var body: some View {
        HStack(spacing: 10) {
            Color.backgroundSecondary
                .overlay { thumbnail }
                .frame(width: Self.imageSize, height: Self.imageSize)
                .clipShape(RoundedRectangle(cornerRadius: Self.imageCornerRadius))
            VStack(alignment: .leading, spacing: 2) {
                text
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: Self.maxCardWidth, alignment: .leading)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: Self.cardCornerRadius))
        .overlay(alignment: .topTrailing) {
            ComposerChipRemoveButton(
                label: "Remove link preview",
                identifier: "composer-link-chip-remove",
                action: onRemove
            )
            .offset(x: Self.removeOverhang, y: -Self.removeOverhang)
        }
        .padding(.top, Self.removeOverhang)
        .padding(.trailing, Self.removeOverhang)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("composer-link-chip")
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch preview.state {
        case .none:
            EmptyView()
        case .loading:
            ProgressView()
        case .ready(_, _, let page):
            if let thumbnail = page.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        if page.isUploadingImage {
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white)
                        }
                    }
            } else {
                Image.icon(.chainLink4)
                    .iconSize(24)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var text: some View {
        switch preview.state {
        case .none:
            EmptyView()
        case .loading(_, let host):
            Text(host)
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
        case .ready(_, let host, let page):
            HStack(spacing: 6) {
                Text(host)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .layoutPriority(1)
                if let description = page.description, !description.isEmpty {
                    Text(description)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .lineLimit(1)
            Text(page.title)
                .font(.appTextCaption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
    }

    private var accessibilityLabel: String {
        switch preview.state {
        case .none:                         ""
        case .loading(_, let host):         "Loading preview for \(host)"
        case .ready(_, let host, let page): "Preview for \(host): \(page.title)"
        }
    }
}

/// The remove button drawn on the top-trailing corner of a staged photo or link thumbnail.
private struct ComposerChipRemoveButton: View {

    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image.icon(.circleXFilled)
                .iconSize(22)
                .foregroundStyle(Color.white)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
