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
