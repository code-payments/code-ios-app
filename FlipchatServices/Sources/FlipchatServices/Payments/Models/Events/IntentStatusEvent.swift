//
//  IntentStatusEvent.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct IntentStatusEvent {
    
    public let eventID: ID
    public let intentID: PublicKey
    public let isError: Bool
    public let date: Date
    
    init(eventID: ID, intentID: PublicKey, isError: Bool, date: Date) {
        self.eventID = eventID
        self.intentID = intentID
        self.isError = isError
        self.date = date
    }
}

extension IntentStatusEvent {
    public struct ID: Codable, Equatable, Hashable {
        
        public var data: Data
        
        init(data: Data) {
            self.data = data
        }
    }
}
