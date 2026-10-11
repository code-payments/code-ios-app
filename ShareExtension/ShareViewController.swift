//
//  ShareViewController.swift
//  ShareExtension
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Intents
import SwiftUI
import UIKit

/// Hosts the SwiftUI share flow. The principal class of a share extension has to be a view
/// controller, so this only wires the extension context into ``ShareModel`` and embeds the view.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        ExtensionReporting.startIfNeeded()

        let context = extensionContext
        let providers = (context?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        // Set when the share sheet was opened from a suggested contact. Donations that populate it are
        // a separate change; until then this is nil and no chat is preselected.
        let intentIdentifier = (context?.intent as? INSendMessageIntent)?.conversationIdentifier

        let model = ShareModel(
            providers: providers,
            intentConversationIdentifier: intentIdentifier,
            finish: { [weak context] in
                context?.completeRequest(returningItems: [])
            },
            cancel: { [weak context] in
                context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            }
        )

        let host = UIHostingController(rootView: ShareRootView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
