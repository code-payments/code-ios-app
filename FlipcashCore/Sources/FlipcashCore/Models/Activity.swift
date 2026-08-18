//
//  Activity.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-23.
//

import Foundation
import FlipcashAPI

public struct Activity: Identifiable, Sendable, Equatable, Hashable {
    public let id: PublicKey
    public let state: State
    public let kind: Kind
    public let title: String
    public let exchangedFiat: ExchangedFiat
    public let date: Date
    public let metadata: Metadata?

    /// The ordered placeholder substitutions the server sent for `title`. `title`
    /// is already rendered with each substitution's `fallback`; a contact-aware
    /// layer can re-render richer names (a contact name for a phone, a display
    /// name for a user) from these.
    public let textSubstitutions: [TextSubstitution]

    /// The other party in a peer activity (the recipient of a send/tip, the
    /// sender of a received tip). `nil` for non-peer activity (deposits, buys,
    /// withdrawals). Used to resolve an avatar and a richer name in feed rows.
    public let counterparty: Counterparty?

    public var cancellableCashLinkMetadata: CashLinkMetadata? {
        switch state {
        case .pending:
            if case .cashLink(let cashLinkMetadata) = metadata, cashLinkMetadata.canCancel {
                return cashLinkMetadata
            }

        case .completed, .unknown:
            break
        }

        return nil
    }

    /// The swap legs + fee when this is a swap activity, else `nil`.
    public var swapMetadata: SwapMetadata? {
        if case .swap(let swapMetadata) = metadata { return swapMetadata }
        return nil
    }

    public init(id: PublicKey, state: State, kind: Kind, title: String, exchangedFiat: ExchangedFiat, date: Date, metadata: Metadata?, textSubstitutions: [TextSubstitution] = [], counterparty: Counterparty? = nil) {
        self.id = id
        self.state = state
        self.kind = kind
        self.title = title
        self.exchangedFiat = exchangedFiat
        self.date = date
        self.metadata = metadata
        self.textSubstitutions = textSubstitutions
        self.counterparty = counterparty
    }
}

// MARK: - Counterparty -

extension Activity {
    /// The other party in a peer activity, as identified by the server.
    public enum Counterparty: Sendable, Equatable, Hashable {
        case user(UserID)
        case phone(String)

        public var userID: UserID? { if case .user(let id) = self { return id } else { return nil } }
        public var phone: String? { if case .phone(let value) = self { return value } else { return nil } }

        /// Rebuilds a counterparty from its persisted columns.
        public init?(userID: UserID?, phone: String?) {
            if let userID { self = .user(userID) }
            else if let phone { self = .phone(phone) }
            else { return nil }
        }
    }
}

extension Activity.Counterparty {
    /// Extracts the counterparty from a send/receive notification's identifier
    /// oneof; `nil` for metadata kinds that have no counterparty.
    init?(_ proto: Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata?) {
        switch proto {
        case .directlySentCrypto(let metadata):
            switch metadata.destinationIdentifier {
            case .userID(let user): guard let id = try? UserID(data: user.value) else { return nil }; self = .user(id)
            case .phone(let phone): self = .phone(phone.value)
            case .none:             return nil
            }
        case .receivedCrypto(let metadata):
            switch metadata.sourceIdentifier {
            case .userID(let user): guard let id = try? UserID(data: user.value) else { return nil }; self = .user(id)
            case .phone(let phone): self = .phone(phone.value)
            case .none:             return nil
            }
        case .withdrewCrypto, .indirectlySentCrypto, .depositedCrypto, .boughtCrypto, .soldCrypto, .swappedCrypto, .none:
            return nil
        }
    }
}

// MARK: - Kind -

extension Activity {
    public enum Kind: Int, Sendable {
        case gave         = 1
        case received     = 2
        case withdrew     = 3
        case cashLink     = 4
        case deposited    = 5
        case paid         = 6
        case distributed  = 7
        case bought       = 8
        case sold         = 9
        /// A swap between two mints, modelled as a single notification. Supersedes
        /// the deprecated `bought`/`sold` pair; also backs a withdraw that executes
        /// as a swap (e.g. USDF withdrawn as USDC).
        case swapped      = 10
        case unknown
    }
}

// MARK: - Kind -

extension Activity {
    public enum State: Int, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        case unknown   = 0
        case pending   = 1
        case completed = 2
        
        public var description: String {
            switch self {
            case .unknown:   "Unknown"
            case .pending:   "Pending"
            case .completed: "Completed"
            }
        }
        
        public var debugDescription: String {
            description
        }
    }
}

extension Activity {
    public enum Metadata: Sendable, Equatable, Hashable {
        case cashLink(CashLinkMetadata)
        case swap(SwapMetadata)
    }
}

// MARK: - TextSubstitution -

extension Activity {
    /// A placeholder substitution for `title`. The server sends `title` with
    /// positional `{0}`, `{1}`, … markers and one substitution per marker; each
    /// carries a `fallback` used when the client can't resolve a richer value.
    public enum TextSubstitution: Sendable, Equatable, Hashable {
        /// Resolve a phone number to a local contact name; `fallback` is the
        /// server-formatted number.
        case phoneNumber(e164: String, fallback: String)
        /// Resolve a user ID to a display name; `fallback` is a server default.
        case userID(UserID, fallback: String)
        /// A substitution kind this client doesn't recognize — use `fallback`.
        case unrecognized(fallback: String)

        /// The rendering used when no richer resolution is available.
        public var fallback: String {
            switch self {
            case .phoneNumber(_, let fallback): fallback
            case .userID(_, let fallback):      fallback
            case .unrecognized(let fallback):   fallback
            }
        }
    }
}

extension Activity.TextSubstitution {
    init(_ proto: Flipcash_Common_V1_Substitution) {
        switch proto.kind {
        case .phoneNumberToContactName(let phone):
            self = .phoneNumber(e164: phone.value, fallback: proto.fallback)
        case .userIDToDisplayName(let userID):
            if let id = try? UserID(data: userID.value) {
                self = .userID(id, fallback: proto.fallback)
            } else {
                self = .unrecognized(fallback: proto.fallback)
            }
        case .none:
            self = .unrecognized(fallback: proto.fallback)
        }
    }
}

// MARK: - Proto -

extension Activity {
    init(_ proto: Flipcash_Activity_V1_Notification) throws {
        let substitutions = proto.textSubstitutions.map(TextSubstitution.init)
        self.init(
            id: try PublicKey(proto.id.value),
            state: .init(rawValue: proto.state.rawValue) ?? .unknown,
            kind: .init(proto.additionalMetadata),
            // Render placeholders with each substitution's fallback so the title
            // never shows raw `{0}` markers. `textSubstitutions` is retained for
            // richer, contact-aware re-rendering.
            title: SubstitutionApplier.apply(
                template: proto.localizedText,
                resolutions: substitutions.map(\.fallback)
            ),
            exchangedFiat: try ExchangedFiat(proto.paymentAmount),
            date: proto.ts.date,
            metadata: .init(proto.additionalMetadata),
            textSubstitutions: substitutions,
            counterparty: .init(proto.additionalMetadata)
        )
    }
}

extension Activity.Kind {
    init(_ proto: Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata?) {
        if let proto {
            switch proto {
            case .directlySentCrypto:
                self = .gave
            case .receivedCrypto:
                self = .received
            case .withdrewCrypto:
                self = .withdrew
            case .indirectlySentCrypto:
                self = .cashLink
            case .depositedCrypto:
                self = .deposited
            case .boughtCrypto:
                self = .bought
            case .soldCrypto:
                self = .sold
            case .swappedCrypto:
                self = .swapped
            }
            
        } else {
            self = .unknown
        }
    }
}

extension Activity.Metadata {
    init?(_ proto: Flipcash_Activity_V1_Notification.OneOf_AdditionalMetadata?) {
        guard let proto else { return nil }

        switch proto {
        case .directlySentCrypto, .receivedCrypto, .withdrewCrypto, .depositedCrypto, .boughtCrypto, .soldCrypto:
            return nil
        case .indirectlySentCrypto(let metadata):
            do {
                self = try .cashLink(.init(metadata))
            } catch {
                return nil
            }
        case .swappedCrypto(let metadata):
            do {
                self = try .swap(.init(metadata))
            } catch {
                return nil
            }
        }
    }
}
