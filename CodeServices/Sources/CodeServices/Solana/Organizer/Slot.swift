//
//  Slot.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Slot: Equatable, Codable, Hashable {
    
    var partialBalance: Kin
    
    public let type: SlotType
    public let cluster: AccountCluster
    
    init(partialBalance: Kin = 0, type: SlotType, mnemonic: MnemonicPhrase) {
        self.partialBalance = partialBalance
        self.type = type
        self.cluster = AccountCluster(authority: .derive(using: type.derivationPath, mnemonic: mnemonic))
    }
    
    func billCount() -> Int {
        partialBalance / type.billValue
    }
}

extension Slot {
    public var billValue: Int {
        type.billValue
    }
}

// MARK: - SlotType -

public enum SlotType: Int, Equatable, CaseIterable, Codable {
    
    case bucket1
    case bucket10
    case bucket100
    case bucket1k
    case bucket10k
    case bucket100k
    case bucket1m
    
    var billValue: Int {
        switch self {
        case .bucket1:
            return 1
        case .bucket10:
            return 10
        case .bucket100:
            return 100
        case .bucket1k:
            return 1_000
        case .bucket10k:
            return 10_000
        case .bucket100k:
            return 100_000
        case .bucket1m:
            return 1_000_000
        }
    }
    
    // TODO: Incorporate indexes and bucket rotation in path
    // TODO: Decouple bucket derivation from size
    var derivationPath: Derive.Path {
        switch self {
        case .bucket1:
            return .bucket1()
        case .bucket10:
            return .bucket10()
        case .bucket100:
            return .bucket100()
        case .bucket1k:
            return .bucket1k()
        case .bucket10k:
            return .bucket10k()
        case .bucket100k:
            return .bucket100k()
        case .bucket1m:
            return .bucket1m()
        }
    }
}
