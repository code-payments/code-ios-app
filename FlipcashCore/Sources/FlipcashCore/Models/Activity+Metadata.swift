//
//  Activity+Metadata.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-29.
//

import Foundation
import FlipcashCoreAPI

extension Activity {
    public struct CashLinkMetadata: Sendable, Equatable, Hashable {
        public let vault: PublicKey
        public let canCancel: Bool
    }
}

extension Activity.CashLinkMetadata {
    init(_ proto: Flipcash_Activity_V1_SentUsdcNotificationMetadata) {
        self.init(
            vault: PublicKey(proto.vault.value)!,
            canCancel: proto.canInitiateCancelAction
        )
    }
}
