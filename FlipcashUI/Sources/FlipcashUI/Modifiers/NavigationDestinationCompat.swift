//
//  NavigationDestinationCompat.swift
//  FlipcashUI
//

import SwiftUI

// TODO: Remove this file when dropping iOS 18 support.

extension View {

    /// A compatibility wrapper around `navigationDestination(item:)` that
    /// always produces a **navigation push** — never a full-screen cover.
    ///
    /// On iOS 19+ this falls through to the standard
    /// `navigationDestination(item:)` (`@escaping` closure, lazy evaluation).
    ///
    /// On iOS 18, `navigationDestination(item:)` has a bug where dismissing
    /// the destination and re-presenting it causes a blank view. This wrapper
    /// bridges the `item` binding to `isPresented` and uses the bug-free
    /// `navigationDestination(isPresented:)` variant instead. The closure is
    /// non-escaping on this path (view struct created on every body eval),
    /// so destination inits must be lightweight.
    @ViewBuilder
    public func navigationDestinationCompat<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 19, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self.navigationDestination(
                isPresented: Binding(
                    get: { item.wrappedValue != nil },
                    set: { if !$0 { item.wrappedValue = nil } }
                )
            ) {
                if let value = item.wrappedValue {
                    destination(value)
                }
            }
        }
    }
}
