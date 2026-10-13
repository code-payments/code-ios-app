//
//  ComposerImagePasteHandlerTests.swift
//  FlipcashTests
//

import Testing
import UIKit
@testable import FlipcashUI

@MainActor
@Suite("Composer image paste")
struct ComposerImagePasteHandlerTests {

    @Test("A pasted image leaves the text and is handed on")
    func imageHandedOn() async {
        let handler = ComposerImagePasteHandler()
        handler.acceptsImages = true
        var received: [[NSItemProvider]] = []
        handler.onImages = { received.append($0) }
        let item = FakePasteItem(.image)

        handler.take(item)
        await Task.yield()

        #expect(item.result == .none)
        #expect(received.count == 1)
        #expect(received.first?.first === item.itemProvider)
    }

    @Test("Pasted text pastes as usual and nothing is handed on")
    func textPastesAsUsual() async {
        let handler = ComposerImagePasteHandler()
        handler.acceptsImages = true
        var received: [[NSItemProvider]] = []
        handler.onImages = { received.append($0) }
        let item = FakePasteItem(.text)

        handler.take(item)
        await Task.yield()

        #expect(item.result == .default)
        #expect(received.isEmpty)
    }

    @Test("A paste of several items hands its images on together, in order, and keeps the text")
    func mixedPasteBatches() async {
        let handler = ComposerImagePasteHandler()
        handler.acceptsImages = true
        var received: [[NSItemProvider]] = []
        handler.onImages = { received.append($0) }
        let first = FakePasteItem(.image)
        let text = FakePasteItem(.text)
        let second = FakePasteItem(.image)

        handler.take(first)
        handler.take(text)
        handler.take(second)
        await Task.yield()

        #expect(text.result == .default)
        #expect(received.count == 1)
        #expect(received.first?.map(ObjectIdentifier.init) == [first, second].map { ObjectIdentifier($0.itemProvider) })
    }

    @Test("When images are not accepted a pasted image is dropped, not put in the text")
    func imageDroppedWhenNotAccepted() async {
        let handler = ComposerImagePasteHandler()
        var received: [[NSItemProvider]] = []
        handler.onImages = { received.append($0) }
        let item = FakePasteItem(.image)

        handler.take(item)
        await Task.yield()

        #expect(item.result == .none)
        #expect(received.isEmpty)
    }

    @Test("Pasted text drops its source styling and takes the field's")
    func pastedTextIsPlain() {
        let handler = ComposerImagePasteHandler()
        let styled = NSAttributedString(string: "bold", attributes: [
            .font: UIFont.boldSystemFont(ofSize: 30),
            .foregroundColor: UIColor.black,
        ])
        let fieldStyle: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]

        let result = handler.plainText([styled, NSAttributedString(string: " text")], attributes: fieldStyle)

        #expect(result.string == "bold text")
        let attributes = result.attributes(at: 0, effectiveRange: nil)
        #expect(attributes[.font] == nil)
        #expect(attributes[.foregroundColor] as? UIColor == .white)
    }

    @Test("Installing turns on attributed editing and routes paste to the handler")
    func installConfiguresTextView() {
        let handler = ComposerImagePasteHandler()
        let textView = UITextView()

        handler.install(on: textView)

        #expect(textView.allowsEditingTextAttributes)
        #expect(textView.pasteDelegate === handler)
        #expect(textView.pasteConfiguration?.acceptableTypeIdentifiers.contains("public.image") == true)
    }
}

private final class FakePasteItem: NSObject, UITextPasteItem {
    enum Kind { case image, text }
    enum Result { case unset, none, `default`, other }

    let itemProvider: NSItemProvider
    let localObject: Any? = nil
    let defaultAttributes: [NSAttributedString.Key: Any] = [:]
    private(set) var result = Result.unset

    init(_ kind: Kind) {
        switch kind {
        case .image:
            itemProvider = NSItemProvider(object: UIImage(systemName: "photo")!)
        case .text:
            itemProvider = NSItemProvider(object: "hello" as NSString)
        }
    }

    func setResult(string: String) { result = .other }
    func setResult(attributedString: NSAttributedString) { result = .other }
    func setResult(attachment: NSTextAttachment) { result = .other }
    func setNoResult() { result = .none }
    func setDefaultResult() { result = .default }
}
