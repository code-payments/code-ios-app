//
//  MessageComposerSheet.swift
//  Flipcash
//

import MessageUI
import SwiftUI

/// SwiftUI wrapper around `MFMessageComposeViewController` for prefilled
/// iMessage invites. Present from a `.sheet(item:)` and clear the bound
/// item from `onFinish` so SwiftUI tears the sheet down once the user
/// taps Send, Cancel, or hits a failure.
///
/// Gate presentation with ``isAvailable`` — the composer is absent on
/// devices that aren't configured for iMessage (iPad without SIM, etc.).
struct MessageComposerSheet: UIViewControllerRepresentable {

    /// Placeholder invite body. Marketing-final copy lands before ship.
    // TODO: Finalize invite copy with product/marketing before App Store ship.
    static let placeholderBody = """
    Download Flipcash so I can send you money

    \(URL.downloadApp.absoluteString)
    """

    /// Whether `MFMessageComposeViewController` can be presented on this
    /// device. Mirrors `MFMessageComposeViewController.canSendText()` so
    /// callers don't need to import `MessageUI` themselves.
    static var isAvailable: Bool { MFMessageComposeViewController.canSendText() }

    let recipient: String
    let body: String
    let onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = body
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
