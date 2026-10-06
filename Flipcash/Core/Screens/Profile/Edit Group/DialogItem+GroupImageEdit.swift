//
//  DialogItem+GroupImageEdit.swift
//  Flipcash
//

import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.edit-group-image")

extension DialogItem {

    /// Which of a group's two images an upload was for, so a failure names the right one in logs.
    enum GroupImage {
        case picture
        case cover

        fileprivate var noun: String {
            switch self {
            case .picture: "group picture"
            case .cover:   "group cover"
            }
        }
    }

    /// Reports a failed group picture or cover save and returns the dialog that explains it.
    ///
    /// Shared by both editors and mirrors ``NewPublicGroupScreen``'s mapping, so the same server
    /// answer reads the same way wherever a group image is submitted.
    static func groupImageEditFailed(_ error: Error, image: GroupImage) -> DialogItem {
        switch error {
        case ErrorEditChat.pictureBlobNotAccepted, ErrorEditChat.coverPictureBlobNotAccepted:
            logger.info("Group image not accepted", metadata: ["image": "\(image.noun)"])
            ErrorReporting.captureError(error, reason: "Group image not accepted")
            return .error(
                title: "This Photo Isn't Allowed",
                subtitle: "Try a different photo"
            )

        case ErrorEditChat.denied:
            logger.info("Group edit denied", metadata: ["image": "\(image.noun)"])
            ErrorReporting.captureError(error, reason: "Group edit denied")
            return .error(
                title: "You Can't Edit This Group",
                subtitle: "Try again later"
            )

        case ErrorEditChat.notFound:
            logger.info("Group edit target not found", metadata: ["image": "\(image.noun)"])
            ErrorReporting.captureError(error, reason: "Group edit target not found")
            return .error(
                title: "This Group No Longer Exists",
                subtitle: "It may have been deleted"
            )

        case let blobError as ErrorBlob:
            logger.info("Group image upload failed", metadata: ["image": "\(image.noun)", "error": "\(blobError)"])
            ErrorReporting.captureError(blobError, reason: "Group image upload failed", userFacing: true)
            return .profilePictureFailed(blobError)

        case let encoderError as ImageEncoderError:
            logger.error("Failed to encode the group image", metadata: ["image": "\(image.noun)", "error": "\(encoderError)"])
            ErrorReporting.captureError(encoderError, reason: "Failed to encode the group image")
            return .imageProcessingFailed

        default:
            logger.error("Failed to edit group image", metadata: ["image": "\(image.noun)", "error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to edit group image")
            return .error(
                title: "Couldn't Save This Photo",
                subtitle: "Try again"
            )
        }
    }
}
