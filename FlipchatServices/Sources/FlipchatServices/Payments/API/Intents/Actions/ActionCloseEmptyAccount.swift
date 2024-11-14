//
//  ActionCloseEmptyAccount.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

//struct ActionCloseEmptyAccount: ActionType {
//    
//    var id: Int
//    var serverParameter: ServerParameter?
//    var signer: KeyPair?
//
//    let type: AccountType
//    let cluster: AccountCluster
//    
//    static let configCountRequirement: Int = 1
//    
//    init(type: AccountType, cluster: AccountCluster) {
//        self.id = 0
//        self.signer = cluster.authority.keyPair
//        
//        self.type = type
//        self.cluster = cluster
//    }
//    
//    func compactMessages() throws -> [CompactMessage] {
//        []
//    }
//}
//
//extension ActionCloseEmptyAccount {
//    enum Error: Swift.Error {
//        case missingConfigurations
//        case invalidTimelockAccounts
//    }
//}
//
//// MARK: - Proto -
//
//extension ActionCloseEmptyAccount {
//    func action() -> Code_Transaction_V2_Action {
//        .with {
//            $0.id = UInt32(id)
//            $0.closeEmptyAccount = .with {
//                $0.accountType = type.accountType
//                $0.authority = cluster.authority.keyPair.publicKey.codeAccountID
//                $0.token = cluster.vaultPublicKey.codeAccountID
//            }
//        }
//    }
//}
