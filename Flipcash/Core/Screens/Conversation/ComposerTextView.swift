#if DEBUG
import SwiftUI
import UIKit
import FlipcashUI

/// Spike: a `UITextView` stand-in for the composer's `TextField`, so the edit menu can carry format
/// items. Debug-only and off by default.
enum ComposerTextViewSwitch {
    /// `-composerTextView YES` on the launch arguments swaps the composer to the `UITextView`.
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "composerTextView") }

    /// `-composerFormatMenu submenu` picks shape (b); anything else is the palette, shape (a).
    static var usesSubmenu: Bool { UserDefaults.standard.string(forKey: "composerFormatMenu") == "submenu" }
}

/// The one place a UTF-16 `NSRange` and a `TextSelection` convert.
enum ComposerSelectionMapping {
    static func range(of selection: TextSelection?, in text: String) -> NSRange? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return nsRange(range, in: text)
        case .multiSelection(let set):
            guard let first = set.ranges.first else { return nil }
            return nsRange(first, in: text)
        @unknown default:
            return nil
        }
    }

    /// A selection's indices belong to the text they were taken from; against a shorter draft they
    /// are out of bounds and trap, so those map to `nil`.
    private static func nsRange(_ range: Range<String.Index>, in text: String) -> NSRange? {
        guard range.upperBound <= text.endIndex else { return nil }
        return NSRange(range, in: text)
    }

    static func selection(of range: NSRange, in text: String) -> TextSelection? {
        guard let r = Range(range, in: text) else { return nil }
        return TextSelection(range: r)
    }
}

struct ComposerTextView: UIViewRepresentable {

    @Binding var text: String
    @Binding var selection: TextSelection?
    @Binding var isFocused: Bool
    let prompt: String
    let maxLines: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FormatTextView {
        let view = FormatTextView()
        view.delegate = context.coordinator
        view.font = .appTextMessage
        view.textColor = UIColor(Color.textMain)
        view.tintColor = .white
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = false
        view.allowsEditingTextAttributes = false
        view.typingAttributes = [.font: UIFont.appTextMessage, .foregroundColor: UIColor(Color.textMain)]
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "composer-message-field"
        view.accessibilityLabel = prompt
        view.placeholder = prompt
        view.text = text
        return view
    }

    func updateUIView(_ view: FormatTextView, context: Context) {
        context.coordinator.parent = self
        view.placeholder = prompt
        view.accessibilityLabel = prompt
        // Never push into a view mid-composition: it cancels the marked text.
        if view.markedTextRange == nil {
            if view.text != text {
                context.coordinator.isPushing = true
                view.text = text
                // A field given text from outside starts with the caret at the end, as `TextField` does.
                view.selectedRange = NSRange(location: (text as NSString).length, length: 0)
                context.coordinator.isPushing = false
            }
            if let range = ComposerSelectionMapping.range(of: selection, in: text),
               range != view.selectedRange, range.upperBound <= (view.text as NSString).length {
                context.coordinator.isPushing = true
                view.selectedRange = range
                context.coordinator.isPushing = false
            }
        }
        if isFocused, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !isFocused, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FormatTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        let content = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let line = UIFont.appTextMessage.lineHeight
        let height = min(max(content, line), line * CGFloat(maxLines))
        return CGSize(width: width, height: ceil(height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        var isPushing = false

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            guard !isPushing else { return }
            if parent.text != textView.text { parent.text = textView.text }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isPushing else { return }
            // The binding's text must be current before its indices mean anything.
            if parent.text != textView.text { parent.text = textView.text }
            if ComposerSelectionMapping.range(of: parent.selection, in: textView.text) != textView.selectedRange {
                parent.selection = ComposerSelectionMapping.selection(of: textView.selectedRange, in: textView.text)
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0, let view = textView as? FormatTextView else { return UIMenu(children: suggestedActions) }
            let actions = FormatAction.allCases.map { kind in
                UIAction(title: kind.title, image: UIImage(systemName: kind.symbol)) { [weak view] _ in
                    view?.apply(kind)
                }
            }
            if ComposerTextViewSwitch.usesSubmenu {
                let format = UIMenu(title: "Format", image: UIImage(systemName: "textformat"), children: actions)
                return UIMenu(children: suggestedActions + [format])
            }
            let palette = UIMenu(options: [.displayInline, .displayAsPalette], children: actions)
            return UIMenu(children: [palette] + suggestedActions)
        }
    }
}

enum FormatAction: CaseIterable {
    case bold, italic, strikethrough, code, link

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .code: "Code"
        case .link: "Link"
        }
    }

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        }
    }

    var marker: String {
        switch self {
        case .bold: "*"
        case .italic: "_"
        case .strikethrough: "~"
        case .code: "`"
        case .link: ""
        }
    }
}

final class FormatTextView: UITextView {

    let placeholderLabel = UILabel()

    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.font = .appTextMessage
        placeholderLabel.textColor = UIColor(Color.textSecondary)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var text: String! {
        didSet { placeholderLabel.isHidden = !(text ?? "").isEmpty }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.isHidden = !text.isEmpty
    }

    /// Pastes the string only, so rich text arrives without its attributes.
    override func paste(_ sender: Any?) {
        guard let string = UIPasteboard.general.string, let range = selectedTextRange else { return }
        replace(range, withText: string)
    }

    /// Wraps the selection in the action's markers, through `UITextInput` so undo records it, and
    /// leaves the selection on the wrapped text.
    func apply(_ action: FormatAction) {
        guard let range = selectedTextRange, !range.isEmpty else { return }
        let selected = text(in: range) ?? ""
        let start = selectedRange.location
        let length = (selected as NSString).length
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        switch action {
        case .link:
            let head = "[\(selected)]("
            replace(range, withText: head + ")")
            selectedRange = NSRange(location: start + (head as NSString).length, length: 0)
        case .bold, .italic, .strikethrough, .code:
            replace(range, withText: action.marker + selected + action.marker)
            selectedRange = NSRange(location: start + (action.marker as NSString).length, length: length)
        }
        delegate?.textViewDidChange?(self)
    }

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + [
            UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(boldCommand)),
            UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(italicCommand)),
        ]
    }

    @objc private func boldCommand() { apply(.bold) }
    @objc private func italicCommand() { apply(.italic) }
}
#endif
