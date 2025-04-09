//
//  PresentationState.swift
//  Code
//
//  Created by Dima Bart on 2025-04-09.
//

import Foundation

enum PresentationState: Equatable {
    
    enum Style {
        case pop
        case slide
    }
    
    case visible(Style)
    case hidden(Style)
    
    var isPresenting: Bool {
        switch self {
        case .visible: return true
        case .hidden:  return false
        }
    }
}
