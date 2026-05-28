//
//  AppGroup.swift
//  FlipcashCore
//

import Foundation

/// Shared between the main app and the NotificationService extension.
public enum AppGroup {

    public static let id = "group.com.flipcash.app.ios"

    /// The URL of the app-group container.
    public static let containerURL: URL = {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else {
            preconditionFailure("Missing app-group entitlement: \(id)")
        }
        return url
    }()
}
