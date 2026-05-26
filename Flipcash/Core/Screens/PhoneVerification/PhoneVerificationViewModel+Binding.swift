//
//  PhoneVerificationViewModel+Binding.swift
//  Flipcash
//

import SwiftUI

extension Binding where Value == PhoneVerificationViewModel? {

    /// Wraps the binding so SwiftUI's `.sheet(item:)` dismissal (swipe-down,
    /// programmatic nil, parent unmount) calls `cancel()` on the outgoing
    /// viewmodel before clearing the slot. `cancel()` is idempotent, so
    /// success paths (where `run()` already resolved) are no-ops.
    func cancellingOnDismiss() -> Binding<PhoneVerificationViewModel?> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                if newValue == nil {
                    wrappedValue?.cancel()
                }
                wrappedValue = newValue
            }
        )
    }
}
