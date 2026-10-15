//
//  ComposerLinkPreview.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import FlipcashCore

/// The preview the composer builds for the first web link in its draft, which the next text send
/// carries for recipients to draw as sent.
///
/// A send never waits on it: a preview still loading, or whose fetch found nothing, goes unsent.
@MainActor
@Observable
final class ComposerLinkPreview {

    /// What a finished fetch found for a link.
    struct Page: Sendable {
        let title: String
        let description: String?
        /// The page's image as uploaded, or `nil` when it had none or the upload failed.
        let image: MediaAttachment?
        /// The page's image for the composer's thumbnail.
        let thumbnail: UIImage?
    }

    /// Fetches the page at `url` and uploads its image, or returns `nil` when there is no preview.
    typealias Load = @MainActor (URL) async -> Page?

    enum State {
        /// No link in the draft has a preview to show.
        case none
        /// The page for `link` is being fetched, or its image uploaded.
        case loading(link: String, host: String)
        /// The preview for `link` is ready to send.
        case ready(link: String, host: String, page: Page)
    }

    private(set) var state: State = .none

    /// Builds the preview for a link; until it is set, nothing is fetched.
    @ObservationIgnored var load: Load?

    /// Links whose preview was removed, kept off for the rest of the draft.
    @ObservationIgnored private var dismissed: Set<String> = []
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The draft link last looked at, including one whose fetch found nothing, so a failure is not
    /// fetched again on every keystroke.
    @ObservationIgnored private var current: String?

    private let detector = LinkDetector()
    private let classifier = LinkCardClassifier()

    /// The link the preview belongs to, as it appears in the draft.
    var link: String? {
        switch state {
        case .none:                          nil
        case .loading(let link, _):          link
        case .ready(let link, _, _):         link
        }
    }

    /// Follows the draft to `text`: keeps the preview while its link is still the draft's first
    /// web card, and otherwise starts on the new one.
    func update(for text: String) {
        let next = Self.webLink(in: text, detector: detector, classifier: classifier)
        guard next?.text != current else { return }
        cancel()
        current = next?.text
        guard let next, !dismissed.contains(next.text), let load else { return }
        let host = WebLinks.host(of: next.url) ?? next.url.host() ?? next.text
        state = .loading(link: next.text, host: host)
        task = Task { [weak self] in
            let page = await load(next.url)
            guard let self, !Task.isCancelled, self.link == next.text else { return }
            if let page {
                self.state = .ready(link: next.text, host: host, page: page)
            } else {
                self.state = .none
            }
        }
    }

    /// Removes the preview, which stays off for this link until the draft is cleared.
    func remove() {
        if let link {
            dismissed.insert(link)
        }
        cancel()
    }

    /// Forgets the draft's preview and every removal, for a fresh draft.
    func reset() {
        dismissed = []
        cancel()
        current = nil
    }

    /// The preview to send with `text`, or `nil` when it is not ready, its link is no longer whole
    /// in `text`, or its title cleans to nothing.
    func attachment(for text: String) -> MessageLinkPreview? {
        guard case .ready(let link, _, let page) = state,
              LinkPreviewSendChecks.isWholeLink(url: link, in: text),
              let title = LinkPreviewSendChecks.cleanTitle(page.title) else { return nil }
        let description = page.description.map(LinkPreviewSendChecks.cleanDescription)
        return MessageLinkPreview(
            url: link,
            title: title,
            description: description?.isEmpty == false ? description : nil,
            image: page.image
        )
    }

    private func cancel() {
        task?.cancel()
        task = nil
        if link != nil {
            state = .none
        }
    }

    /// The first link in `text` the classifier makes a web card, with the text it was found in.
    nonisolated static func webLink(in text: String, detector: LinkDetector, classifier: LinkCardClassifier) -> (text: String, url: URL)? {
        guard case .web(let web)? = classifier.firstCard(in: detector.webLinks(in: text)) else { return nil }
        return ((text as NSString).substring(with: web.range), web.url)
    }
}

extension ComposerLinkPreview {

    /// A loader that fetches pages through `metadata`, downloads their image through `images`, and
    /// uploads it through `uploader` as `senderID`'s chat photo.
    static func loader(
        metadata: any LinkMetadataSource,
        images: WebImageSource,
        uploader: @escaping @MainActor () -> ChatMediaUploader,
        senderID: UserID
    ) -> Load {
        { url in
            guard case .resolved(let page)? = try? await metadata.metadata(for: url) else { return nil }
            var image: MediaAttachment?
            var thumbnail: UIImage?
            if let imageURL = page.imageURL,
               let data = await images.data(for: imageURL),
               let picture = UIImage(data: data) {
                var size: (width: Int, height: Int)?
                if let uploaded = try? await uploader().upload(picture, onPrepared: { size = ($0, $1) }),
                   let size {
                    image = MediaAttachment(uploaded, width: size.width, height: size.height, senderID: senderID)
                    thumbnail = picture
                }
            }
            guard !Task.isCancelled else { return nil }
            return Page(title: page.title, description: page.description, image: image, thumbnail: thumbnail)
        }
    }
}

extension MediaAttachment {

    /// The attachment for `photo` as uploaded by `senderID` at `width`×`height`.
    init(_ photo: UploadedPhoto, width: Int, height: Int, senderID: UserID) {
        switch photo {
        case .plain(let blobID):
            self.init(blobID: blobID, width: width, height: height, blurhash: nil)
        case .sealed(let sealed):
            self.init(
                blobID: sealed.blobID,
                width: sealed.width,
                height: sealed.height,
                blurhash: sealed.blurhash.isEmpty ? nil : sealed.blurhash,
                sealed: SealedBlob(senderID: senderID, plaintextSize: sealed.sizeBytes)
            )
        }
    }
}
