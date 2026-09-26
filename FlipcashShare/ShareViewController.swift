//
//  ShareViewController.swift
//  FlipcashShare
//

import UIKit
import UniformTypeIdentifiers

import FlipcashCore

/// Takes the shared image, writes it into the App Group container, and opens the app.
///
/// Deliberately does no decoding. The scanner, the route allowlist, and everything that acts
/// on a decoded payload live in the app and need the app's session; duplicating any of it
/// here would mean two copies of the check that stops a shared `/login` QR, which is the
/// exact check least worth having two copies of.
///
/// No UI either — the extension appears, copies, and dismisses. Anything worth showing the
/// user is shown by the app a moment later.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            await handOff()
            finish()
        }
    }

    private func handOff() async {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            }),
            let inbox = SharedImageInbox()
        else {
            return
        }

        guard let data = await Self.imageData(from: provider) else {
            return
        }

        try? inbox.deposit(data)
    }

    /// Prefers the file representation, which hands over the original bytes without decoding
    /// them into memory. A provider that offers only an in-memory `UIImage` is re-encoded as
    /// a fallback, which is lossy but rare.
    private static func imageData(from provider: NSItemProvider) async -> Data? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)

        switch item {
        case let url as URL:
            return try? Data(contentsOf: url)
        case let data as Data:
            return data
        case let image as UIImage:
            return image.jpegData(compressionQuality: 0.95)
        default:
            return nil
        }
    }

    private func finish() {
        // Opening the host app from an extension has no supported API, so the responder chain
        // is walked for an object that responds to `openURL:`. Fragile by nature: if a future
        // iOS removes it, the app still finds the deposited image on its next launch, which
        // is why the inbox is a file rather than something tied to this call succeeding.
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(SharedImageInbox.handoffURL())
                break
            }
            responder = current.next
        }

        extensionContext?.completeRequest(returningItems: nil)
    }
}
