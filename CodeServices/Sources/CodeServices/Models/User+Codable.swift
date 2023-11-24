//
//  User+Codable.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension User: Codable {
    
    public init(from decoder: Decoder) throws {
        let container   = try decoder.container(keyedBy: CodingKeys.self)
        
        let id          = try container.decode(ID.self,    forKey: .id)
        let containerID = try container.decode(ID.self,    forKey: .containerID)
        let phone       = try container.decode(Phone.self, forKey: .phone)
        
        self.init(
            id: id,
            containerID: containerID,
            phone: phone,
            betaFlagsAllowed: false,
            eligibleAirdrops: []
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id,          forKey: .id)
        try container.encode(containerID, forKey: .containerID)
        try container.encode(phone,       forKey: .phone)
    }
}

extension User {
    enum CodingKeys: String, CodingKey {
        case id
        case containerID
        case phone
        case debugOptionsEnabled
    }
}
