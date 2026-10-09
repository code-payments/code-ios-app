//
//  ShareInput.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers

/// What a share sheet hands the share extension, sorted into the images to send and the text to
/// prefill the message with.
public struct ShareInput: Equatable, Sendable {

    /// Copies of the shared images in the extension's temporary directory, in share order. Files, not
    /// bitmaps: the extension decodes one at a time so a 10-photo share never holds 10 decodes.
    public var imageURLs: [URL]

    /// The text to prefill the message with: the shared link when there is one, otherwise the shared
    /// text. A web page arrives as a URL plus a plain-text title, and the link is the part worth sending.
    public var text: String?

    /// Images past the attachment limit that were left out.
    public var droppedImageCount: Int

    public init(imageURLs: [URL] = [], text: String? = nil, droppedImageCount: Int = 0) {
        self.imageURLs = imageURLs
        self.text = text
        self.droppedImageCount = droppedImageCount
    }

    public var isEmpty: Bool { imageURLs.isEmpty && (text?.isEmpty ?? true) }

    /// The most photos one send can carry; matches the composer's limit in the app.
    public static let maxImages = 10

    /// Sorts `providers` into images and text. A provider counts as an image first, a web link
    /// second, text last, so a provider that offers several representations is read once. File
    /// URLs are never a link: a file shared from Files arrives as one and is not message text.
    @MainActor
    public static func parse(
        _ providers: [NSItemProvider],
        maxImages: Int = ShareInput.maxImages,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) async -> ShareInput {
        var input = ShareInput()
        var link: String?
        var text: String?

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                guard input.imageURLs.count < maxImages else {
                    input.droppedImageCount += 1
                    continue
                }
                if let url = await copyImage(from: provider, into: temporaryDirectory) {
                    input.imageURLs.append(url)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if link == nil, let url = await loadWebURL(from: provider) {
                    link = url.absoluteString
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if text == nil, let string = await loadText(from: provider) {
                    text = string
                }
            }
        }

        let prefill = (link ?? text)?.trimmingCharacters(in: .whitespacesAndNewlines)
        input.text = prefill?.isEmpty == false ? prefill : nil
        return input
    }

    /// Removes the temporary image copies.
    public func removeFiles(fileManager: FileManager = .default) {
        for url in imageURLs {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Loading -

    /// The URL `loadFileRepresentation` hands over is deleted when its handler returns, so the copy
    /// has to happen inside it.
    @MainActor
    private static func copyImage(from provider: NSItemProvider, into directory: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let copy = directory.appendingPathComponent("share-\(UUID().uuidString)").appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    @MainActor
    private static func loadWebURL(from provider: NSItemProvider) async -> URL? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
        let url: URL? = switch item {
        case let url as URL:     url
        case let url as NSURL:   url as URL
        case let string as String: URL(string: string)
        default:                 nil
        }
        guard let url, !url.isFileURL else { return nil }
        return url
    }

    @MainActor
    private static func loadText(from provider: NSItemProvider) async -> String? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        return switch item {
        case let string as String: string
        case let data as Data:     String(data: data, encoding: .utf8)
        default:                   nil
        }
    }
}
