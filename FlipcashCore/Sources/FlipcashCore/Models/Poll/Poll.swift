//
//  Poll.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// The server-assigned identifier of a poll.
public struct PollID: Hashable, Sendable {

    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(_ proto: Flipcash_Poll_V1_PollId) {
        self.data = proto.value
    }

    var proto: Flipcash_Poll_V1_PollId {
        .with { $0.value = data }
    }
}

/// A poll as the server reports it: what was asked, who asked, and the current tally.
public struct Poll: Hashable, Sendable {

    public let id: PollID
    public let conversationID: ConversationID
    /// `nil` when the wire user id isn't a valid UUID.
    public let creator: UserID?
    public let definition: PollDefinition
    public let createdAt: Date
    public let state: PollState

    init(_ proto: Flipcash_Poll_V1_PollMetadata) {
        self.id = PollID(proto.pollID)
        self.conversationID = ConversationID(proto.chatID)
        self.creator = try? UUID(data: proto.creator.value)
        self.definition = PollDefinition(proto.definition)
        self.createdAt = proto.createdAt.date
        self.state = PollState(proto.state)
    }
}

/// How votes are weighted.
public enum PollMode: Hashable, Sendable {
    /// One vote per member.
    case count
    /// Votes weigh by the voter's balance of a mint.
    case balance
    /// A mode this client doesn't recognize.
    case unknown

    init(_ proto: Flipcash_Poll_V1_Mode) {
        switch proto {
        case .count:   self = .count
        case .balance: self = .balance
        case .unknown, .UNRECOGNIZED: self = .unknown
        }
    }

    var proto: Flipcash_Poll_V1_Mode {
        switch self {
        case .count:   .count
        case .balance: .balance
        case .unknown: .unknown
        }
    }
}

/// The question and options of a poll, either in the clear or sealed under the chat key.
public enum PollText: Hashable, Sendable {
    case plaintext(question: String, options: [String])
    /// Sealed text of a private group. The scheme is the wire `EncryptedPollText.Scheme` raw value.
    case encrypted(scheme: Int, nonce: Data, ciphertext: Data)
}

/// The mint and currency a `.balance` poll weighs votes in.
public struct PollBalanceParameters: Hashable, Sendable {
    public let mint: PublicKey
    public let currency: String

    public init(mint: PublicKey, currency: String) {
        self.mint = mint
        self.currency = currency
    }
}

/// Everything a creator chooses when opening a poll.
public struct PollDefinition: Hashable, Sendable {

    public let mode: PollMode
    public let allowsMultipleChoices: Bool
    public let endsAt: Date
    /// Set when `mode` is `.balance`.
    public let balanceParameters: PollBalanceParameters?
    /// `nil` when the wire definition carries neither plaintext nor encrypted text.
    public let text: PollText?
    /// Carried separately because the server cannot count the options of sealed text.
    public let optionCount: Int

    public init(
        mode: PollMode,
        allowsMultipleChoices: Bool,
        endsAt: Date,
        balanceParameters: PollBalanceParameters? = nil,
        optionCount: Int,
        text: PollText
    ) {
        self.mode = mode
        self.allowsMultipleChoices = allowsMultipleChoices
        self.endsAt = endsAt
        self.balanceParameters = balanceParameters
        self.optionCount = optionCount
        self.text = text
    }

    init(_ proto: Flipcash_Poll_V1_PollDefinition) {
        self.mode = PollMode(proto.mode)
        self.allowsMultipleChoices = proto.allowsMultipleChoices
        self.endsAt = proto.endsAt.date
        self.optionCount = Int(proto.optionCount)
        self.balanceParameters = proto.hasBalanceParameters
            ? (try? PublicKey(proto.balanceParameters.mint.value)).map {
                PollBalanceParameters(mint: $0, currency: proto.balanceParameters.currency)
            }
            : nil
        switch proto.text {
        case .plaintext(let plaintext):
            self.text = .plaintext(question: plaintext.question, options: plaintext.options.map(\.text))
        case .encrypted(let encrypted):
            self.text = .encrypted(scheme: encrypted.scheme.rawValue, nonce: encrypted.nonce, ciphertext: encrypted.ciphertext)
        case .none:
            self.text = nil
        }
    }

    /// The wire definition for `CreatePoll`.
    var proto: Flipcash_Poll_V1_PollDefinition {
        .with {
            $0.mode = mode.proto
            $0.allowsMultipleChoices = allowsMultipleChoices
            $0.endsAt = .init(date: endsAt)
            if let balanceParameters {
                $0.balanceParameters = .with {
                    $0.mint = .with { $0.value = balanceParameters.mint.data }
                    $0.currency = balanceParameters.currency
                }
            }
            $0.optionCount = UInt32(optionCount)
            switch text {
            case .plaintext(let question, let options):
                $0.plaintext = .with {
                    $0.question = question
                    $0.options = options.map { option in .with { $0.text = option } }
                }
            case .encrypted(let scheme, let nonce, let ciphertext):
                $0.encrypted = .with {
                    $0.scheme = Flipcash_Poll_V1_EncryptedPollText.Scheme(rawValue: scheme) ?? .unknown
                    $0.nonce = nonce
                    $0.ciphertext = ciphertext
                }
            case .none:
                break
            }
        }
    }
}

/// Where a poll stands: open, tallying, or closed, with the viewer's own vote and the results.
public struct PollState: Hashable, Sendable {

    public enum Status: Hashable, Sendable {
        case open
        case tallying
        case closed
        case unknown
    }

    public enum Results: Hashable, Sendable {
        case count(totalVoters: UInt64, optionVoters: [UInt64])
        /// `total` and `optionBalances` hold `nil` where an amount fails to decode.
        case balance(totalVoters: UInt64, total: ExchangedFiat?, optionBalances: [ExchangedFiat?])
        case ranked(totalVoters: UInt64, optionRanks: [UInt32])
        /// The server holds the tally back (for example until the poll closes).
        case withheld
        /// Results of a kind this client doesn't recognize, or none at all.
        case unknown
    }

    public let status: Status
    /// Option indices the viewer voted for.
    public let selfVote: [Int]
    public let closedAt: Date?
    public let results: Results

    init(_ proto: Flipcash_Poll_V1_PollState) {
        switch proto.status {
        case .open:     self.status = .open
        case .tallying: self.status = .tallying
        case .closed:   self.status = .closed
        case .unknown, .UNRECOGNIZED: self.status = .unknown
        }
        self.selfVote = proto.selfVote.map(Int.init)
        self.closedAt = proto.hasClosedAt ? proto.closedAt.date : nil
        switch proto.results.type {
        case .count(let count):
            self.results = .count(totalVoters: count.totalVoters, optionVoters: count.optionVoters)
        case .balance(let balance):
            self.results = .balance(
                totalVoters: balance.totalVoters,
                total: balance.hasTotal ? try? ExchangedFiat(balance.total) : nil,
                optionBalances: balance.optionBalances.map { try? ExchangedFiat($0) }
            )
        case .ranked(let ranked):
            self.results = .ranked(totalVoters: ranked.totalVoters, optionRanks: ranked.optionRanks)
        case .withheld:
            self.results = .withheld
        case .none:
            self.results = .unknown
        }
    }
}
