//
//  DialogItem+ProfilePicture.swift
//  Flipcash
//

import FlipcashCore
import FlipcashUI

extension DialogItem {

    /// Returns the dialog explaining why a profile picture didn't upload.
    ///
    /// The distinctions matter to the reader: only moderation means the picture
    /// itself was disallowed, and only the transient failures are worth
    /// retrying — telling someone to try again when the server refused them
    /// outright just wastes their time.
    static func profilePictureFailed(_ error: ErrorBlob) -> DialogItem {
        switch error {
        case .rejected(let reason):
            profilePictureRejected(reason)

        case .uploadDenied:
            .error(
                title: "Photo Uploads Aren't Available",
                subtitle: "This account can't upload a photo yet"
            )

        case .quotaExceeded:
            .error(
                title: "Upload Limit Reached",
                subtitle: "Try again later"
            )

        case .unsupportedType:
            .error(
                title: "This Image Format Isn't Supported",
                subtitle: "Use a PNG or JPEG image"
            )

        case .tooLarge:
            .error(
                title: "This Image is Too Large",
                subtitle: "Try a smaller image"
            )

        case .timedOut, .uploadFailed, .notFound, .notUploaded, .unknown, .network:
            .error(
                title: "Couldn't Upload Your Photo",
                subtitle: "Try again"
            )
        }
    }

    private static func profilePictureRejected(_ reason: BlobRejectionReason) -> DialogItem {
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
