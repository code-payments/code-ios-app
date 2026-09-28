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
    /// The photo is still being prepared or uploaded.
    case progress
    /// The upload failed and can be tried again.
    case retry
    /// The server refused the photo; the only way forward is to remove it.
    case error
    /// The photo is uploaded, so the thumbnail stands alone.
    case none

    /// Returns the badge for a chip in `state`.
    init(_ state: ComposerChip.State) {
        switch state {
        case .preparing, .uploading:        self = .progress
        case .uploaded:                     self = .none
        case .failed(.retryable):           self = .retry
        case .failed(.notRetryable):        self = .error
        }
    }
}

/// The photos staged for the next send, as a row of thumbnails above the message field.
///
/// Part of the bar's own content rather than a reveal like the reply strip: its arrival changes the
/// bar's height the way a draft wrapping to a second line does, which the screen takes in one frame.
struct ComposerChipStrip: View {

    /// Side of a chip's square thumbnail, per the spec's 56pt chips.
    static let chipSize: CGFloat = 56

    let chips: [ComposerChip]
    let onRemove: (ComposerChip.ID) -> Void
    let onRetry: (ComposerChip) -> Void

    /// Returns whether the strip is drawn: while chips are staged, and not during an edit, which
    /// takes the bar for itself and hands the chips back when it ends.
    static func isShown(chipCount: Int, isEditing: Bool) -> Bool {
        chipCount > 0 && !isEditing
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    ComposerChipView(
                        chip: chip,
                        onRemove: { onRemove(chip.id) },
                        onRetry: { onRetry(chip) }
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: Self.chipSize)
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
        ZStack {
            Color.backgroundSecondary
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            }
            badge
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: SystemSymbol.closeCircle.rawValue)
                    .font(.default(size: 18, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.55))
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove photo")
            .accessibilityIdentifier("composer-chip-remove")
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
        case .progress:
            ZStack {
                Color.black.opacity(0.35)
                ProgressView()
                    .tint(.white)
            }
            .accessibilityLabel("Uploading photo")
        case .retry:
            Button(action: onRetry) {
                ZStack {
                    Color.black.opacity(0.45)
                    Image(systemName: "arrow.clockwise")
                        .font(.default(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry photo upload")
            .accessibilityIdentifier("composer-chip-retry")
        case .error:
            ZStack {
                Color.black.opacity(0.45)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.default(size: 18, weight: .semibold))
                    .foregroundStyle(Color.textError)
            }
            .accessibilityLabel("Photo can't be sent")
        case .none:
            EmptyView()
        }
    }
}
