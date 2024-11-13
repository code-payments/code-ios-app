//
//  PartialAccount.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

struct PartialAccount: Equatable, Codable, Hashable {
    
    let cluster: AccountCluster
    
    var partialBalance: Kin
    
    init(cluster: AccountCluster, partialBalance: Kin = 0) {
        self.cluster = cluster
        self.partialBalance = partialBalance
    }
}
