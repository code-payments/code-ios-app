//
//  EmailVerificationViewModel+Binding.swift
//  Flipcash
//

import SwiftUI

extension Binding where Value == EmailVerificationViewModel? {

    /// Wraps the binding so SwiftUI's `.sheet(item:)` dismissal (swipe-down,
    /// programmatic nil, parent unmount) calls `cancel()` on the outgoing
    /// viewmodel before clearing the slot. `cancel()` is idempotent, so
    /// success paths (where `run()` already resolved) are no-ops.
    func cancellingOnDismiss() -> Binding<EmailVerificationViewModel?> {
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
