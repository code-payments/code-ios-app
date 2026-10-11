//
//  ShareSendPlan.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The messages one share becomes, in send order.
public enum ShareSendPlan {

    public enum Step: Equatable, Sendable {
        /// The photo at `index` in the shared images, with `caption` under it.
        case photo(index: Int, caption: String?)
        case text(String)
    }

    /// One message per image with the text as the caption of the last, the way the composer sends
    /// staged photos; a text message when there are no images; nothing when there is neither.
    public static func steps(imageCount: Int, text: String?) -> [Step] {
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = text?.isEmpty == false ? text : nil
        guard imageCount > 0 else {
            return caption.map { [.text($0)] } ?? []
        }
        return (0..<imageCount).map { index in
            .photo(index: index, caption: index == imageCount - 1 ? caption : nil)
        }
    }
}
