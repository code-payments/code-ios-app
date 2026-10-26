//
//  GroupPaymentRequest+Lifecycle.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension GroupPaymentRequest {

    /// How long an ended request stays in a chat's deck after it closed.
    public static let deckRetention: TimeInterval = 24 * 60 * 60

    /// The status as of `now`: an OPEN request whose deadline has passed reads as EXPIRED.
    public func effectiveStatus(at now: Date) -> Status {
        switch status {
        case .open:
            if let endsAt = split?.endsAt, endsAt <= now {
                return .expired
            }
            return .open
        case .completed, .closed, .expired, .unknown:
            return status
        }
    }

    /// When the request ended as of `now`, taking the deadline for a request that expired on the clock.
    public func effectiveClosedAt(at now: Date) -> Date? {
        switch status {
        case .open:
            guard let endsAt = split?.endsAt, endsAt <= now else { return nil }
            return endsAt
        case .completed, .closed, .expired, .unknown:
            return closedAt ?? split?.endsAt
        }
    }

    /// Whether the request has stopped taking payments as of `now`.
    public func isEnded(at now: Date) -> Bool {
        switch effectiveStatus(at: now) {
        case .open:                                    false
        case .completed, .closed, .expired, .unknown:  true
        }
    }

    /// The sum of every share's amount, in the split's currency.
    public var requestedNative: Decimal {
        (split?.shares ?? []).reduce(Decimal.zero) { $0 + Decimal($1.nativeAmount) }
    }

    /// The sum of the paid shares' amounts, in the split's currency.
    public var paidNative: Decimal {
        (split?.shares ?? []).filter(\.isPaid).reduce(Decimal.zero) { $0 + Decimal($1.nativeAmount) }
    }

    /// The paid share of the total, from 0 to 1; a COMPLETED request is always 1.
    public var paidFraction: Double {
        if status == .completed { return 1 }
        let requested = requestedNative
        guard requested > 0 else { return 0 }
        return min(1, (paidNative / requested).doubleValue)
    }

    /// The share owed by `userID`, if any.
    public func share(for userID: UserID) -> Share? {
        split?.shares.first { $0.userID == userID }
    }

    /// The copy of a request to keep when `incoming` arrives for one already held as `existing`.
    ///
    /// The greater version wins whole; at an equal version EXPIRED beats OPEN, since expiry can land
    /// without a version bump.
    public static func merged(existing: GroupPaymentRequest, incoming: GroupPaymentRequest) -> GroupPaymentRequest {
        if incoming.version != existing.version {
            return incoming.version > existing.version ? incoming : existing
        }
        if existing.status == .expired && incoming.status == .open {
            return existing
        }
        return incoming
    }
}

// MARK: - Deadline -

extension GroupPaymentRequest {

    /// What the status line says, before it is put into words.
    public enum Deadline: Hashable, Sendable {
        case daysLeft(Int)
        case hoursLeft(Int)
        case minutesLeft(Int)
        case paidInFull
        case closed
        case expired
    }

    /// The status line's state as of `now`. More than 24 hours left reads in days rounded up, so
    /// "1 day" never appears; 1–24 hours in hours rounded up; under an hour in minutes rounded up.
    public func deadline(at now: Date) -> Deadline {
        switch effectiveStatus(at: now) {
        case .completed:          return .paidInFull
        case .closed:             return .closed
        case .expired, .unknown:  return .expired
        case .open:
            guard let endsAt = split?.endsAt else { return .expired }
            let remaining = endsAt.timeIntervalSince(now)
            let hour: TimeInterval = 60 * 60
            let day: TimeInterval = 24 * hour
            if remaining > day {
                return .daysLeft(Int((remaining / day).rounded(.up)))
            }
            if remaining >= hour {
                return .hoursLeft(Int((remaining / hour).rounded(.up)))
            }
            return .minutesLeft(max(1, Int((remaining / 60).rounded(.up))))
        }
    }
}

// MARK: - Deck -

extension GroupPaymentRequest {

    /// Whether `userID` has an unpaid share in this request while it is open as of `now`. The creator
    /// never owes on their own request.
    public func isOwed(by userID: UserID, at now: Date) -> Bool {
        guard userID != creator, effectiveStatus(at: now) == .open, let share = share(for: userID) else { return false }
        return !share.isPaid
    }

    /// The requests a chat's deck shows as of `now`, in deck order: open requests `viewer` owes on,
    /// then other open requests, each by nearest deadline, then those that ended within
    /// ``deckRetention``, most recently ended first.
    public static func deckOrder(_ requests: [GroupPaymentRequest], viewer: UserID? = nil, at now: Date) -> [GroupPaymentRequest] {
        var open: [GroupPaymentRequest] = []
        var ended: [(request: GroupPaymentRequest, closedAt: Date)] = []

        for request in requests {
            switch request.effectiveStatus(at: now) {
            case .open:
                open.append(request)
            case .completed, .closed, .expired:
                guard let closedAt = request.effectiveClosedAt(at: now),
                      now.timeIntervalSince(closedAt) < deckRetention else { continue }
                ended.append((request, closedAt))
            case .unknown:
                continue
            }
        }

        open.sort { lhs, rhs in
            if let viewer {
                let lhsOwed = lhs.isOwed(by: viewer, at: now)
                if lhsOwed != rhs.isOwed(by: viewer, at: now) { return lhsOwed }
            }
            return (lhs.split?.endsAt ?? .distantFuture) < (rhs.split?.endsAt ?? .distantFuture)
        }
        ended.sort { $0.closedAt > $1.closedAt }
        return open + ended.map(\.request)
    }
}
