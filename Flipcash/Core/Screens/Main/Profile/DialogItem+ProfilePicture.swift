//
//  DialogItem+ProfilePicture.swift
//  Flipcash
//

import FlipcashCore
import FlipcashUI

extension DialogItem {

    /// Returns the dialog explaining why the server refused a profile picture.
    ///
    /// Only moderation means the picture itself was disallowed; the rest are
    /// processing failures, and telling a user their photo "isn't allowed"
    /// when it merely failed to transcode sends them looking for a new photo
    /// they don't need.
    static func profilePictureRejected(_ reason: BlobRejectionReason) -> DialogItem {
        switch reason {
        case .moderation:
            .error(
                title: "This Image is Not Allowed",
                subtitle: "Try a different image"
            )
        case .unsupportedType, .mismatchedType:
            .error(
                title: "This Image Format Isn't Supported",
                subtitle: "Use a PNG or JPEG image"
            )
        case .tooLarge:
            .error(
                title: "This Image is Too Large",
                subtitle: "Try a smaller image"
            )
        case .corrupt:
            .error(
                title: "Couldn't Read This Image",
                subtitle: "Try a different image"
            )
        case .privacyMetadata:
            .error(
                title: "This Image Carries Extra Data",
                subtitle: "Try a different image"
            )
        case .unknown:
            .error(
                title: "Couldn't Upload Your Photo",
                subtitle: "Try again"
            )
        }
    }
}
