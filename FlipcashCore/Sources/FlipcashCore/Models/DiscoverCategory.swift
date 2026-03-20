//
//  DiscoverCategory.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

public enum DiscoverCategory: String, CaseIterable, Hashable, Sendable {
    case popular
    case new

    var protoCategory: Ocp_Currency_V1_DiscoverRequest.Category {
        switch self {
        case .popular: return .popular
        case .new:     return .new
        }
    }
}
