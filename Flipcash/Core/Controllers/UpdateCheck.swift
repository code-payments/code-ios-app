//
//  UpdateCheck.swift
//  Flipcash
//

import Foundation

/// The thresholds that decide when the update toast shows, kept together so both triggers and the
/// eligibility check read the same numbers.
nonisolated enum UpdatePolicy {
    /// The release manifest priority, on Play's 0–5 scale, from which an update counts as priority.
    static let priorityThreshold = 4
    /// How long a newer store version has been out before an update counts without priority.
    static let stalenessThreshold: TimeInterval = 7 * 24 * 60 * 60
    /// The shortest gap between two store checks.
    static let checkInterval: TimeInterval = 6 * 60 * 60
    /// The pause after the user comes back to a tab home before the toast shows.
    static let returnSettle: Duration = .seconds(1)
    /// How long the user stays on a tab home before the toast shows.
    static let homeDwell: Duration = .seconds(3)
    /// The pause after a chat opens before the toast shows.
    static let chatSettle: Duration = .seconds(1)
    /// How long the toast stays on a tab home.
    static let homeTimeout: Duration = .seconds(10)
    /// How long the toast stays in a chat, where it covers the newest messages.
    static let chatTimeout: Duration = .seconds(6)
}

/// A dotted marketing version, such as `2026.10.4`, compared numerically per component.
nonisolated struct AppVersion: Comparable, Codable, Sendable, CustomStringConvertible {

    /// The numeric components, most significant first.
    let components: [Int]

    /// The version `string` names, or `nil` when it is empty or any component is not a number.
    init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        components = numbers
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    // A missing trailing component reads as zero, so `2026.10` equals `2026.10.0`.
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    init(from decoder: any Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let version = AppVersion(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a version"))
        }
        self = version
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// The newest version the App Store offers, and when it was released.
nonisolated struct StoreRelease: Codable, Equatable, Sendable {
    let version: AppVersion
    let releasedAt: Date

    /// The App Store lookup endpoint for the app in `country`, an ISO 3166 alpha-2 code.
    static func lookupURL(country: String) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: "6758636374"),
            URLQueryItem(name: "country", value: country.lowercased()),
        ]
        return components.url!
    }

    /// The release the lookup response `data` describes, or `nil` when it lists no usable result.
    static func parseLookup(_ data: Data) -> StoreRelease? {
        struct Response: Decodable {
            struct Result: Decodable {
                let version: String
                let currentVersionReleaseDate: String
            }
            let results: [Result]
        }
        guard let result = (try? JSONDecoder().decode(Response.self, from: data))?.results.first,
              let version = AppVersion(result.version),
              let releasedAt = ISO8601DateFormatter().date(from: result.currentVersionReleaseDate)
        else { return nil }
        return StoreRelease(version: version, releasedAt: releasedAt)
    }
}

/// The release manifest published from the repo, which marks how urgent the production version is.
nonisolated struct ReleaseManifest: Equatable, Sendable {
    let productionVersion: AppVersion
    let priority: Int

    /// Where the manifest is read from.
    static let url = URL(string: "https://raw.githubusercontent.com/code-payments/code-ios-app/main/.well-known/release-manifest.json")!

    /// The manifest `data` holds, or `nil` when it doesn't parse.
    static func parse(_ data: Data) -> ReleaseManifest? {
        struct Body: Decodable {
            struct Production: Decodable {
                let version: String
                let priority: Int
            }
            let production: Production
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let version = AppVersion(body.production.version)
        else { return nil }
        return ReleaseManifest(productionVersion: version, priority: body.production.priority)
    }

    /// The priority this manifest gives `version`: its own priority when it names that version, else 0.
    func priority(for version: AppVersion) -> Int {
        productionVersion == version ? priority : 0
    }
}

/// What the last store check found, cached between launches.
nonisolated struct UpdateCheckResult: Codable, Equatable, Sendable {
    let release: StoreRelease
    let priority: Int
    let checkedAt: Date
}

/// Decides, from a store check, whether a newer version exists and whether it merits the toast.
nonisolated enum UpdateEligibility {

    /// The store version when it is newer than `installed`, else `nil`.
    static func newerVersion(installed: AppVersion?, release: StoreRelease?) -> AppVersion? {
        guard let installed, let release, release.version > installed else { return nil }
        return release.version
    }

    /// Whether the toast may show for `result`: the store build is newer, the update is priority or has
    /// been out for the staleness threshold, and the toast hasn't shown for that version yet.
    static func isToastEligible(
        installed: AppVersion?,
        result: UpdateCheckResult?,
        lastShownVersion: AppVersion?,
        now: Date
    ) -> Bool {
        guard let result, let newer = newerVersion(installed: installed, release: result.release) else { return false }
        guard lastShownVersion != newer else { return false }
        let isPriority = result.priority >= UpdatePolicy.priorityThreshold
        let isStale = now.timeIntervalSince(result.release.releasedAt) >= UpdatePolicy.stalenessThreshold
        return isPriority || isStale
    }
}
