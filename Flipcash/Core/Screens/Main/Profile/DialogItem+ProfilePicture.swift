//
//  DialogItem+ProfilePicture.swift
//  Flipcash
//

import FlipcashCore
import FlipcashUI

extension DialogItem {

    /// Returns the dialog for an image the app itself couldn't encode.
    static var imageProcessingFailed: DialogItem {
        .error(
            title: "Couldn't Process Image",
            subtitle: "Try a smaller or simpler image"
        )
    }

    /// Returns the dialog explaining why a profile picture didn't upload.
    static func profilePictureFailed(_ error: ErrorBlob) -> DialogItem {
        switch error {
        case .rejected(.moderation):
            .error(
                title: "This Image is Not Allowed",
                subtitle: "Try a different image"
            )

        case .rejected(.corrupt):
            .error(
                title: "Couldn't Read This Image",
                subtitle: "Try a different image"
            )

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

        case .unsupportedType, .rejected(.unsupportedType), .rejected(.mismatchedType):
            .error(
                title: "This Image Format Isn't Supported",
                subtitle: "Use a PNG or JPEG image"
            )

        case .tooLarge, .rejected(.tooLarge):
            .error(
                title: "This Image is Too Large",
                subtitle: "Try a smaller image"
            )

        // Privacy metadata is stripped from every upload, so a rejection for it
        // is a defect on our side rather than something a different photo fixes.
        case .rejected(.privacyMetadata), .rejected(.unknown), .timedOut,
             .uploadFailed, .notFound, .notUploaded, .unknown, .network:
            .error(
                title: "Couldn't Upload Your Photo",
                subtitle: "Try again"
            )
        }
    }
}
