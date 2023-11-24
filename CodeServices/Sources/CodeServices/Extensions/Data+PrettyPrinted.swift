//
//  Data+PrettyPrinted.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Data {
    public var stringRepresentation: String {
        String(data: self, encoding: .utf8) ?? "nil"
    }
}
