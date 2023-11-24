//
//  KeyPair+Rendezvous.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension KeyPair {
    public static func deriveRendezvousKey(from payload: Data) -> KeyPair {
        let hash = SHA256.digest(payload)
        let seed = Seed32(hash)!
        return KeyPair(seed: seed)
    }
}
