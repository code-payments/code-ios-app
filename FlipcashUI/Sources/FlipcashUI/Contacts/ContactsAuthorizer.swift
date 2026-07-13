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

    public init() {}

    // MARK: - Authorize -

    /// Reads the current authorization status into ``status``. Runs the TCC
    /// query off the main actor.
    public func refresh() async {
        // Previews seed `status` directly; skip the real TCC read so a pinned
        // state (e.g. `.denied`) renders instead of resolving to the host's.
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        let resolved = await Task.detached {
            CNContactStore.authorizationStatus(for: .contacts)
        }.value
        status = resolved
    }

    /// Prompts the user once when the status is `.notDetermined`, then returns
    /// the resolved authorization status. iOS suppresses repeat prompts.
    /// `.limited` (iOS 18+) grants partial access and is usable like
    /// `.authorized`; only `.denied` / `.restricted` callers should route to
    /// Settings.
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
