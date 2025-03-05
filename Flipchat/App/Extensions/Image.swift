//
//  Image.swift
//  Code
//
//  Created by Dima Bart on 2025-03-03.
//

import SwiftUI
import CodeUI

extension Image {
    static func verificationBadge(for type: VerificationType) -> Image? {
        switch type {
        case .none:
            return nil
        case .blue:
            return Image.asset(.twitterBlue)
        case .business:
            return Image.asset(.twitterGold)
        case .government:
            return Image.asset(.twitterGrey)
        }
    }
}
