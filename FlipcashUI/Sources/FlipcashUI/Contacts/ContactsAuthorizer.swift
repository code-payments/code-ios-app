//
//  ContactsAuthorizer.swift
//  FlipcashUI
//

import SwiftUI
import Contacts

@MainActor
@Observable
public final class ContactsAuthorizer {

    public var status: CNAuthorizationStatus = .notDetermined

    // MARK: - Init -

    /// Constructs the authorizer without reading `CNContactStore.authorizationStatus`.
    /// On iOS 26.5+ a first-launch read of the authorization status can surface
    /// the system permission prompt before any priming UI is on screen; callers
    /// must invoke ``refresh()`` once the priming view is presenting.
    public init() {}

    // MARK: - Authorize -

    /// Reads the current authorization status into ``status``. The read runs
    /// off the main actor — `CNContactStore.authorizationStatus(for:)` makes
    /// a synchronous XPC roundtrip to the TCC daemon and iOS 17+ logs
    /// "This method should not be called on the main thread" when invoked
    /// from `@MainActor`.
    public func refresh() async {
        let resolved = await Task.detached {
            CNContactStore.authorizationStatus(for: .contacts)
        }.value
        status = resolved
    }

    /// Prompts the user once when the status is `.notDetermined`, then returns
    /// the resolved authorization status. For `.denied` / `.restricted` /
    /// `.limited` callers should route the user to Settings — iOS suppresses
    /// repeat prompts.
    ///
    /// Marked `@MainActor` because `CNContactStore.requestAccess` resumes the
    /// continuation on an arbitrary queue; the post-`await` `refresh()`
    /// must mutate the `@Observable` `status` on the main actor.
    public func authorize() async -> CNAuthorizationStatus {
        let current = await Task.detached {
            CNContactStore.authorizationStatus(for: .contacts)
        }.value
        guard current == .notDetermined else {
            status = current
            return current
        }

        let store = CNContactStore()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.requestAccess(for: .contacts) { _, _ in
                continuation.resume()
            }
        }

        await refresh()
        return status
    }
}
