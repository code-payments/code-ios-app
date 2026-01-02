//
//  EnvironmentValues.swift
//  Code
//
//  Created by Raul Riera on 2025-12-31.
//

import SwiftUI

extension EnvironmentValues {
    /// An action that dismisses the current presentation container.
    ///
    /// Use this environment value to access an ``Action`` scoped to the
    /// current presentation container, rather than the topmost presented view.
    /// Calling the action dismisses the view that originally injected it.
    ///
    /// This is intended to complement ``DismissAction`` when you need to pass
    /// a dismissal capability deep into a navigation or presentation stack,
    /// allowing a child view to dismiss a specific ancestor (the caller),
    /// not necessarily the currently presented view.
    ///
    /// ### Example
    /// ```swift
    /// struct ParentView: View {
    ///     @Environment(\.dismissAction) private var dismiss
    ///
    ///     var body: some View {
    ///         NavigationStack {
    ///             ChildView()
    ///                 .environment(\.dismissParentContainer, {
    ///                     dismiss()
    ///                 })
    ///         }
    ///     }
    /// }
    ///
    /// struct ChildView: View {
    ///     @Environment(\.dismissParentContainer) private var dismiss
    ///
    ///     var body: some View {
    ///         Button("Close parent") {
    ///             dismiss()
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// In this example, `ChildView` dismisses `ParentView`, even though it is
    /// not the currently presented view.
    @Entry var dismissParentContainer: () -> Void = {}
}
