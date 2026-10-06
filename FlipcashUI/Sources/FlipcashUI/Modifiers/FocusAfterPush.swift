//
//  FocusAfterPush.swift
//  FlipcashUI
//

import SwiftUI

extension View {

    /// Focuses `focus` once the push that brought this screen in has finished, so the keyboard and
    /// anything pinned above it rise on a screen that is already in place.
    public func focusAfterPush(_ focus: FocusState<Bool>.Binding) -> some View {
        task {
            // A navigation push runs about 0.5s; focusing during it slides the keyboard's
            // accessories in from off screen alongside the incoming view.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            focus.wrappedValue = true
        }
    }
}
