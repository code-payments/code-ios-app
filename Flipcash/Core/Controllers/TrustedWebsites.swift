//
//  TrustedWebsites.swift
//  Flipcash
//

import Foundation

/// The hosts whose links open without the "You're Leaving Flipcash" warning.
///
/// One list for the device, shared by every account on it and kept only in `UserDefaults`.
/// Logout and Switch Accounts leave it alone. Each entry is an exact host as
/// ``ExternalLinkCheck`` normalizes it, so trusting `x.com` says nothing about `mail.x.com`.
@Observable
final class TrustedWebsites {

    /// A host the user chose to stop being warned about.
    struct Entry: Codable, Equatable, Identifiable {
        let host: String
        let addedAt: Date

        var id: String { host }
    }

    /// Every trusted host, newest first.
    private(set) var entries: [Entry]

    /// The trusted hosts, for ``ExternalLinkCheck``.
    var hosts: Set<String> {
        Set(entries.map(\.host))
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    // MARK: - Init -

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.entries = Self.load(from: defaults)
    }

    // MARK: - Mutations -

    /// Adds `host` as of now. A host already in the list keeps its original date.
    func trust(_ host: String) {
        guard !entries.contains(where: { $0.host == host }) else { return }
        entries.insert(Entry(host: host, addedAt: now()), at: 0)
        save()
    }

    /// Removes `host`, so the next link to it warns again.
    func remove(_ host: String) {
        entries.removeAll { $0.host == host }
        save()
    }

    // MARK: - Persistence -

    private static func load(from defaults: UserDefaults) -> [Entry] {
        guard
            let data = defaults.data(forKey: DefaultsKey.trustedWebsites.rawValue),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            return []
        }
        return entries.sorted { $0.addedAt > $1.addedAt }
    }

    private func save() {
        let key = DefaultsKey.trustedWebsites.rawValue
        if entries.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
