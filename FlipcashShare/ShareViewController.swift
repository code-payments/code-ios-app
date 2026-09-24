//
//  ShareViewController.swift
//  FlipcashShare
//

import UIKit

/// Placeholder: the target exists and activates for a single image, but the handover
/// arrives in the next commit.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extensionContext?.completeRequest(returningItems: nil)
    }
}
