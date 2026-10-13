import UIKit
import UniformTypeIdentifiers

/// Takes images pasted into the composer's field out of the text and hands them on as photos,
/// leaving everything else to paste as usual.
@MainActor
final class ComposerImagePasteHandler: NSObject, UITextPasteDelegate {

    /// Whether pasted images are handed on; when false they are dropped, never put in the text.
    var acceptsImages = false

    /// Receives the images one paste carried, in paste order.
    var onImages: (([NSItemProvider]) -> Void)?

    private var pending: [NSItemProvider] = []

    /// Makes `textView` take pasted images and route them here. The keyboard's paste suggestion
    /// only offers an image to a field that edits attributed text, so this turns that on too.
    func install(on textView: UITextView) {
        textView.allowsEditingTextAttributes = true
        // Attributed editing is what the suggestion was seen to need; the image type here matches
        // the configuration it was seen working with.
        var types = textView.pasteConfiguration?.acceptableTypeIdentifiers ?? []
        if !types.contains(UTType.image.identifier) {
            types.append(UTType.image.identifier)
            textView.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: types)
        }
        textView.pasteDelegate = self
    }

    func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
        transform item: any UITextPasteItem
    ) {
        take(item)
    }

    func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
        combineItemAttributedStrings itemStrings: [NSAttributedString],
        for textRange: UITextRange
    ) -> NSAttributedString {
        let typingAttributes = (textPasteConfigurationSupporting as? UITextView)?.typingAttributes ?? [:]
        return plainText(itemStrings, attributes: typingAttributes)
    }

    /// Joins pasted text with its source styling dropped, in the field's own style. The chat sends
    /// plain text, so styling pasted into the field would only show until it was sent.
    func plainText(_ itemStrings: [NSAttributedString], attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: itemStrings.map(\.string).joined(), attributes: attributes)
    }

    /// Routes one pasted item: an image leaves the text, anything else pastes as it would have.
    func take(_ item: any UITextPasteItem) {
        guard item.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            item.setDefaultResult()
            return
        }
        item.setNoResult()
        guard acceptsImages else { return }
        // Each item of a paste arrives on its own; collect them so one paste stages as one batch.
        if pending.isEmpty {
            Task { @MainActor in self.flush() }
        }
        pending.append(item.itemProvider)
    }

    private func flush() {
        let providers = pending
        pending = []
        guard !providers.isEmpty else { return }
        onImages?(providers)
    }
}
