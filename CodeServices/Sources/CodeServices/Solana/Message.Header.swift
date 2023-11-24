//
//  Message.Header.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Message {
    public struct Header: Equatable {
        
        static let length: Int = 3
        
        public var requiredSignatures: Int
        public var readOnlySigners: Int
        public var readOnly: Int
        
        internal init(requiredSignatures: Int, readOnlySigners: Int, readOnly: Int) {
            self.requiredSignatures = requiredSignatures
            self.readOnlySigners = readOnlySigners
            self.readOnly = readOnly
        }
    }
}

// MARK: - Description -

extension Message.Header: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        return "H{\(requiredSignatures), \(readOnlySigners), \(readOnly)}"
    }
    
    public var debugDescription: String {
        description
    }
}

// MARK: - SolanaCodable -

extension Message.Header {
    public init?(data: Data) {
        guard data.count == 3 else {
            return nil
        }
        
        let counts = data.bytes.map { Int($0) }
        
        self.requiredSignatures = counts[0]
        self.readOnlySigners    = counts[1]
        self.readOnly           = counts[2]
    }
    
    public func encode() -> Data {
        [
            requiredSignatures,
            readOnlySigners,
            readOnly,
        ]
        .map { Byte($0) }
        .data
    }
}
