//
//  CronActor.swift
//  Code
//
//  Created by Dima Bart on 2024-06-14.
//

import Foundation

@globalActor
struct CronActor {
    actor ActorType { }
    
    static let shared: ActorType = ActorType()
}
