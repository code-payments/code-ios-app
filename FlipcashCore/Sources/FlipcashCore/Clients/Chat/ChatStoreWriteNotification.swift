//
//  ChatStoreWriteNotification.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// A cross-process signal that the notification extension wrote pushed messages into the shared
/// chat store, so a running app can re-read them from disk.
///
/// Darwin notifications carry no payload and coalesce while undelivered: an observer learns that
/// at least one write happened since it last heard, never what was written.
public enum ChatStoreWriteNotification {

    private static let name = CFNotificationName("\(NotificationPreviewCache.appGroup).chat-store-write" as CFString)

    private static var center: CFNotificationCenter { CFNotificationCenterGetDarwinNotifyCenter() }

    /// Tells every process observing the signal that the extension wrote to the store.
    public static func post() {
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
    }

    /// Calls `handler` on each signal until the returned token is passed to ``stopObserving(_:)`` or
    /// released. The handler runs on an arbitrary thread.
    public static func observe(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        let observer = Observer(handler: handler)
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(observer).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<Observer>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name.rawValue,
            nil,
            .deliverImmediately
        )
        return observer
    }

    /// Stops the observation `token` came from.
    public static func stopObserving(_ token: AnyObject) {
        CFNotificationCenterRemoveObserver(center, Unmanaged.passUnretained(token).toOpaque(), name, nil)
    }

    private final class Observer: Sendable {
        let handler: @Sendable () -> Void

        init(handler: @escaping @Sendable () -> Void) {
            self.handler = handler
        }

        // The center holds this object unretained, so a registration that outlived it would call
        // into freed memory on the next signal.
        deinit {
            ChatStoreWriteNotification.stopObserving(self)
        }
    }
}
