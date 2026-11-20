//
//  ChatPhotoBubbleLayout.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics

/// How wide a transcript draws a photo bubble, and so which copy of the photo it loads.
///
/// The transcript lays its rows out with these numbers, and whatever downloads a photo before its
/// chat opens picks the copy with them, so both ask for the same blob.
public enum ChatPhotoBubbleLayout {

    /// The widest row a bubble is sized against: rows that fill a share of the width are laid out as
    /// on a phone-width transcript.
    public static let maxRowWidth: CGFloat = 440

    /// The share of the row a bubble may fill.
    public static let widthFraction: CGFloat = 0.78

    /// The leading gutter an attributed incoming row gives to its author's avatar: the 28 pt avatar
    /// and 8 pt of space.
    public static let authorGutterWidth: CGFloat = 36

    /// The widest a photo bubble gets in a transcript `rowWidth` points wide. `attributedIncoming` is
    /// a group chat's message from someone else, whose row gives its gutter to the avatar.
    public static func maxWidth(rowWidth: CGFloat, attributedIncoming: Bool) -> CGFloat {
        let row = min(rowWidth, maxRowWidth)
        return (attributedIncoming ? row - authorGutterWidth : row) * widthFraction
    }

    /// The pixel size a bubble's copy must reach: the bubble's width, which a photo always spans, as
    /// Android's bubble asks for `maxWidth.roundToPx()`. A view not yet on a screen reports a scale of
    /// 0; that is taken as 3, so its copy never draws soft once it is.
    public static func targetPixels(maxWidth: CGFloat, scale: CGFloat) -> Int {
        Int((maxWidth * (scale > 0 ? scale : 3)).rounded())
    }

    /// The copy the bubble for `attachment` loads once its message is drawn in a transcript
    /// `rowWidth` points wide, on a screen of `scale` pixels per point: the copy a download made
    /// before the chat opens has to land, so the bubble finds it. Nil before the upload has a blob.
    public static func rendition(of attachment: MediaAttachment, rowWidth: CGFloat, attributedIncoming: Bool, scale: CGFloat) -> MediaRendition? {
        let maxWidth = maxWidth(rowWidth: rowWidth, attributedIncoming: attributedIncoming)
        return attachment.rendition(forPixelSize: targetPixels(maxWidth: maxWidth, scale: scale))
    }
}
