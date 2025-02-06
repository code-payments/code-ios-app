//
//  String+Emoji.swift
//  Code
//
//  Created by Dima Bart on 2024-12-19.
//

import Foundation

extension String {
    var isOnlyEmoji: Bool {
        guard !self.isEmpty else {
            return false
        }
        
        let indexes = compactMap { $0.unicodeScalars.first { !$0.properties.isEmojiPresentation } }
        return indexes.isEmpty
    }
    
    static let unicodeHex: String = "⬢"
    
    static func formattedPeopleCount(count: Int) -> String {
        "\(count) \(count == 1 ? "person" : "people") here"
    }
    
    static func formattedListenerCount(count: Int) -> String {
        "\(count) \(count == 1 ? "Listener" : "Listeners")"
    }
}
