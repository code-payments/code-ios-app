//
//  PasterboardObserver.swift
//  Code
//
//  Created by Dima Bart on 2025-05-16.
//

import UIKit
import FlipcashCore

@Observable
class PasteboardObserver {
    
    var hasStrings = UIPasteboard.general.hasStrings
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(pasteboardChanged), name: UIPasteboard.changedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pasteboardChanged), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    @objc private func pasteboardChanged() {
        trace(.note, components: "Pasteboard did change")
        hasStrings = UIPasteboard.general.hasStrings
    }
}
