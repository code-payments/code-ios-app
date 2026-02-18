//
//  NavigationDestinationCompat.swift
//  FlipcashUI
//

import SwiftUI

// TODO: Remove this file when dropping iOS 18 support.

extension View {

    /// A compatibility wrapper around `navigationDestination(item:)` that works
    /// around an iOS 18 bug where dismissing the destination (setting the item
    /// to `nil`) and then presenting it again (second push) causes a blank view.
    ///
    /// On iOS 18 a `fullScreenCover` is used instead. The cover wraps the
    /// destination in a `NavigationStack` so toolbar and navigation title
    /// modifiers continue to work. Setting the item to `nil` dismisses the
    /// cover the same way it would pop a navigation destination.
    ///
    /// On iOS 19+ this falls through to the standard `navigationDestination(item:)`.
    @ViewBuilder
    public func navigationDestinationCompat<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 19, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self.fullScreenCover(item: item) { value in
                NavigationStack {
                    destination(value)
                }
            }
        }
    }
}
