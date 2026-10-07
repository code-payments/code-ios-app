//
//  DialogItem+Connection.swift
//  Flipcash
//

import Foundation
import FlipcashUI

extension DialogItem {

    /// Returns a dialog for a request that never reached the server. If the app's Cellular Data
    /// switch is off, it says so and links to Settings. Otherwise it returns `fallback`.
    static func connectionFailure(_ fallback: DialogItem, path: NetworkPathState) -> DialogItem {
        guard path.isCellularDenied else { return fallback }
        return .error(
            title: fallback.title ?? "No Connection",
            subtitle: "Cellular data is turned off for Flipcash. Turn it on in Settings to use Flipcash away from Wi-Fi."
        ) {
            .destructive("Open Settings") {
                URL.openSettings()
            };
            .dismiss(kind: .subtle)
        }
    }
}
