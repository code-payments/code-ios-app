//
//  MessageComposerSheet.swift
//  Flipcash
//

import MessageUI
import SwiftUI

/// SwiftUI wrapper around `MFMessageComposeViewController` for prefilled
/// iMessage invites. Gate presentation with ``isAvailable``.
struct MessageComposerSheet: UIViewControllerRepresentable {

    /// Placeholder invite body.
    static let placeholderBody = """
    You should download Flipcash, a new way to send cash

    \(URL.downloadApp.absoluteString)
    """

    /// Whether the composer can be presented on this device.
    static var isAvailable: Bool { MFMessageComposeViewController.canSendText() }

    let recipient: String
    let onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = Self.placeholderBody
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {

        let onFinish: (MessageComposeResult) -> Void

        init(onFinish: @escaping (MessageComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult,
        ) {
            controller.dismiss(animated: true) { [onFinish] in
                onFinish(result)
            }
        }
    }
}
