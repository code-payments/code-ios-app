//
//  ChatComposerBar.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

#if canImport(UIKit)
import UIKit

/// A dumb input bar: a rounded text field and a send button on a translucent background, so
/// the transcript shows through it. Owns no behaviour beyond emitting the trimmed text on send;
/// the screen above it decides what to do. All UIKit — no SwiftUI.
public final class ChatComposerBar: UIView {

    /// Called with the trimmed, non-empty text when the user taps send.
    public var onSend: ((String) -> Void)?

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let field = UITextField()
    private let sendButton = UIButton(type: .system)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        field.placeholder = "Message"
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.backgroundColor = .tertiarySystemFill
        field.borderStyle = .none
        field.layer.cornerRadius = 18
        field.layer.cornerCurve = .continuous
        field.returnKeyType = .send
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        // Inset the text inside the rounded field.
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 0))
        field.rightViewMode = .always

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30))
        sendButton.configuration = config
        sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [field, sendButton])
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            field.heightAnchor.constraint(equalToConstant: 38),

            // Pin the controls to the bar's safe area so they clear the home indicator when the
            // bar sits at the very bottom, and hug the keyboard when it's up.
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    private func send() {
        let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        onSend?(text)
        field.text = ""
    }
}

extension ChatComposerBar: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        send()
        return false
    }
}

#Preview("Composer bar") {
    let container = UIView()
    container.backgroundColor = .systemBackground
    let bar = ChatComposerBar()
    bar.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(bar)
    NSLayoutConstraint.activate([
        bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        bar.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    return container
}
#endif
