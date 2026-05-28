//
//  NotificationPayload.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// Decodes `Flipcash_Push_V1_Payload` from a `UNNotificationContent.userInfo`.
public enum NotificationPayload {

    /// Key the server writes into APS custom data.
    public static let userInfoKey = "flipcash_payload"

    /// Returns the typed payload, or `nil` if the dictionary doesn't carry one
    /// or the bytes don't decode.
    public static func decode(_ userInfo: [AnyHashable: Any]) -> Flipcash_Push_V1_Payload? {
        guard let base64 = userInfo[userInfoKey] as? String,
              let data = Data(base64Encoded: base64) else {
            return nil
        }
        return try? Flipcash_Push_V1_Payload(serializedBytes: data)
    }
}
