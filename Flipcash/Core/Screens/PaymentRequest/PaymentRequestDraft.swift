//
//  PaymentRequestDraft.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The deadline a new request is created with.
enum PaymentRequestDeadline: Hashable, Sendable {
    case oneDay
    case threeDays
    case oneWeek
    case twoWeeks
    case fourWeeks
    case custom(Date)

    /// The presets, in the order the Time To Pay sheet lists them before Custom.
    static let presets: [PaymentRequestDeadline] = [.oneDay, .threeDays, .oneWeek, .twoWeeks, .fourWeeks]

    /// The server's limit less five minutes, so a device clock slightly ahead of the server's passes.
    static let maximumLead: TimeInterval = 28 * 24 * 60 * 60 - 5 * 60
    /// The soonest a custom deadline can be picked.
    static let minimumCustomLead: TimeInterval = 60 * 60

    /// `ends_at` for a request sent at `now`.
    func endsAt(sentAt now: Date) -> Date {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .oneDay:           return now.addingTimeInterval(day)
        case .threeDays:        return now.addingTimeInterval(3 * day)
        case .oneWeek:          return now.addingTimeInterval(7 * day)
        case .twoWeeks:         return now.addingTimeInterval(14 * day)
        case .fourWeeks:        return now.addingTimeInterval(Self.maximumLead)
        case .custom(let date): return date
        }
    }

    /// The row's label on the Time To Pay sheet.
    var rowTitle: String {
        switch self {
        case .oneDay:    "1 Day"
        case .threeDays: "3 Days"
        case .oneWeek:   "1 Week"
        case .twoWeeks:  "2 Weeks"
        case .fourWeeks: "4 Weeks"
        case .custom:    "Custom"
        }
    }

    /// The Timing value on the summary.
    func summaryValue(locale: Locale = .current) -> String {
        switch self {
        case .oneDay:    return "1 Day To Pay"
        case .threeDays: return "3 Days To Pay"
        case .oneWeek:   return "7 Days To Pay"
        case .twoWeeks:  return "14 Days To Pay"
        case .fourWeeks: return "28 Days To Pay"
        case .custom(let date):
            let formatted = date.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
                    .year(.omitted)
            )
            return "Until \(formatted)"
        }
    }
}

/// Who a new request asks, and the words the summary says about them.
struct PaymentRequestPeople: Hashable, Sendable {

    /// The most shares a request can hold, the creator's included.
    static let maximumShares = 100

    /// Every member in roster order, the creator among them.
    let members: [UserID]
    let creator: UserID
    private(set) var selected: Set<UserID>

    /// Everyone selected, unless the group is larger than a request can hold, which starts empty.
    init(members: [UserID], creator: UserID) {
        self.members = members
        self.creator = creator
        self.selected = members.count > Self.maximumShares ? [] : Set(members)
    }

    var includesCreator: Bool { selected.contains(creator) }

    /// The members asked other than the creator.
    var askedCount: Int { selected.subtracting([creator]).count }

    /// Whether at least one member other than the creator is selected.
    var isValid: Bool { askedCount > 0 }

    /// Checks or unchecks `userID`. Returns `false`, leaving the selection as it was, when checking
    /// would make more than ``maximumShares`` shares.
    @discardableResult
    mutating func toggle(_ userID: UserID) -> Bool {
        if selected.contains(userID) {
            selected.remove(userID)
            return true
        }
        guard selected.count < Self.maximumShares else { return false }
        selected.insert(userID)
        return true
    }

    /// The summary's People value.
    var summaryValue: String {
        guard isValid else { return "Choose People" }
        let othersCount = members.filter { $0 != creator }.count
        let everyoneElse = askedCount == othersCount
        switch (everyoneElse, includesCreator) {
        case (true, true):   return "Everyone, Including You"
        case (true, false):  return "Everyone Except You"
        case (false, true):  return "\(Self.people(askedCount)), Including You"
        case (false, false): return Self.people(askedCount)
        }
    }

    /// The summary's second People line, shown when the creator is included.
    var summarySecondLine: String? {
        isValid && includesCreator ? "You'll be marked as paid" : nil
    }

    /// The selected members in roster order, the creator first when included.
    var orderedSelection: [UserID] {
        let others = members.filter { $0 != creator && selected.contains($0) }
        return includesCreator ? [creator] + others : others
    }

    /// One unpaid share per selected member, each of `nativeAmount`.
    func shares(nativeAmount: Double) -> [GroupPaymentRequest.Share] {
        orderedSelection.map { GroupPaymentRequest.Share(userID: $0, nativeAmount: nativeAmount) }
    }

    /// "Request $20 from 25 People", counting only the members asked.
    func buttonTitle(amount: String) -> String {
        "Request \(amount) from \(Self.people(askedCount))"
    }

    private static func people(_ count: Int) -> String {
        count == 1 ? "1 Person" : "\(count) People"
    }
}

/// The default title of a new request: the weekday followed by " Request".
func defaultPaymentRequestTitle(at now: Date = .now, locale: Locale = .current) -> String {
    "\(now.formatted(Date.FormatStyle(locale: locale).weekday(.wide))) Request"
}
