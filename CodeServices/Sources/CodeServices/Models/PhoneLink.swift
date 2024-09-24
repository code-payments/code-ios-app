//
//  PhoneLink.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct PhoneLink: Sendable {
    
    public let phone: Phone
    public let isLinked: Bool
    
    // MARK: - Init -
    
    public init(phone: Phone, isLinked: Bool) {
        self.phone = phone
        self.isLinked = isLinked
    }
}
