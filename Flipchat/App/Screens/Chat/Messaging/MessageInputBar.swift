//
//  MessageInputBar.swift
//  Code
//
//  Created by Dima Bart on 2025-02-19.
//

import UIKit
import CodeUI

protocol MessageInputBarDelegate: AnyObject {
    func textContentHeightDidChange()
    func willSendMessage(text: String) -> Bool
}

class MessageInputBar: UIView {
    
    weak var delegate: MessageInputBarDelegate?
    
    private let textView = ExpandingTextView()
    private let sendButton = UIButton(type: .custom)
    
    private var heightConstraint: NSLayoutConstraint!
    private var isFirstLayout: Bool = true
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupViews()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func layoutSubviews() {
        let currentHeight = heightConstraint?.constant
        let newHeight = textView.desiredHeight
        
        if currentHeight != newHeight {
            heightConstraint?.constant = newHeight
        }
        
        super.layoutSubviews()
        
        if currentHeight != newHeight {
            if isFirstLayout {
                delegate?.textContentHeightDidChange()
            } else {
                // Call delegate after layout
                // on the next runloop
                DispatchQueue.main.async {
                    self.delegate?.textContentHeightDidChange()
                }
            }
            isFirstLayout = false
        }
    }
    
    private func setupViews() {
        backgroundColor = .backgroundMain
        
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.backgroundColor = .white
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.layer.cornerRadius = 18
        textView.layer.masksToBounds = true
        textView.font = .appTextMessage
        textView.textColor = .backgroundMain
        textView.tintColor = .backgroundMain
        textView.textContainerInset = .zero
        textView.textContainerInset = .init(
            top: 8,
            left: 10,
            bottom: 8,
            right: 10
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .white
        addSubview(textView)
        
        sendButton.setImage(.asset(.paperplane), for: .normal)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendAction), for: .touchUpInside)
        addSubview(sendButton)
        
        heightConstraint = textView.heightAnchor.constraint(equalToConstant: 35)
        heightConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            heightConstraint,
            
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -15),
            
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            sendButton.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }
    
    @objc private func sendAction() {
        let text = textView.text ?? ""
        
        Task {
            let shouldClear = delegate?.willSendMessage(text: text) ?? false
            if shouldClear {
                textView.text = ""
            }
        }
    }
    
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }
    
    override func resignFirstResponder() -> Bool {
        textView.resignFirstResponder()
    }
}

extension MessageInputBar: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        self.setNeedsLayout()
    }
}

// MARK: - ExpandingTextView -

class ExpandingTextView: UITextView {
    var desiredHeight: CGFloat {
        let textContainterInsets = textContainerInset
        var usedRect = layoutManager.usedRect(for: textContainer)
        
        usedRect.size.height += textContainterInsets.top + textContainterInsets.bottom
        
        let scale  = UIScreen.main.scale
        let height = ceil(usedRect.size.height * scale) / scale
        print("Intrinsic height: \(height), raw: \(usedRect.size.height)")
        return height
    }
}
