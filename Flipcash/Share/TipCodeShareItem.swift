//
//  TipCodeShareItem.swift
//  Flipcash
//

import UIKit
import LinkPresentation

/// Shares a tip code link with a header built from the rendered tip code image.
///
/// Supplying `LPLinkMetadata` makes iOS skip its own network fetch for the
/// preview. Recipients always receive the URL — never the image — so the link
/// resolves its own Open Graph preview in the destination app.
final class TipCodeShareItem: NSObject, UIActivityItemSource {

    private let url: URL
    private let title: String?
    private let preview: TipCodePreview?

    init(url: URL, title: String?, preview: TipCodePreview?) {
        self.url = url
        self.title = title
        self.preview = preview
        super.init()
    }

    /// Shares a person's profile link, titled for them — the one way every profile share is built.
    static func profile(url: URL, displayName: String?, preview: TipCodePreview? = nil) -> TipCodeShareItem {
        TipCodeShareItem(url: url, title: profileTitle(for: displayName), preview: preview)
    }

    /// "Chat with <name> on Flipcash", or nil when there is no name, so the link goes untitled.
    static func profileTitle(for displayName: String?) -> String? {
        guard let displayName, !displayName.isEmpty else { return nil }
        return String(localized: "Chat with \(displayName) on Flipcash", comment: "Share sheet title for a person's profile link")
    }

    // MARK: - UIActivityItemSource -

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title ?? ""
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        guard let preview else { return nil }

        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: preview.hero)
        metadata.iconProvider = NSItemProvider(object: preview.icon)
        return metadata
    }
}
