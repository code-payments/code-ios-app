// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: account/v1/account_service.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

public struct Code_Account_V1_IsCodeAccountRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The owner account to check against.
  public var owner: Code_Common_V1_SolanaAccountId {
    get {return _owner ?? Code_Common_V1_SolanaAccountId()}
    set {_owner = newValue}
  }
  /// Returns true if `owner` has been explicitly set.
  public var hasOwner: Bool {return self._owner != nil}
  /// Clears the value of `owner`. Subsequent reads from it will return its default value.
  public mutating func clearOwner() {self._owner = nil}

  /// The signature is of serialize(IsCodeAccountRequest) without this field set
  /// using the private key of the owner account. This provides an authentication
  /// mechanism to the RPC.
  public var signature: Code_Common_V1_Signature {
    get {return _signature ?? Code_Common_V1_Signature()}
    set {_signature = newValue}
  }
  /// Returns true if `signature` has been explicitly set.
  public var hasSignature: Bool {return self._signature != nil}
  /// Clears the value of `signature`. Subsequent reads from it will return its default value.
  public mutating func clearSignature() {self._signature = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _owner: Code_Common_V1_SolanaAccountId? = nil
  fileprivate var _signature: Code_Common_V1_Signature? = nil
}

public struct Code_Account_V1_IsCodeAccountResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Account_V1_IsCodeAccountResponse.Result = .ok

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    /// The account is a Code account.
    case ok // = 0

    /// The account is not a Code account.
    case notFound // = 1

    /// The account exists, but at least one timelock account is unlocked
    case unlockedTimelockAccount // = 2
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      case 1: self = .notFound
      case 2: self = .unlockedTimelockAccount
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .notFound: return 1
      case .unlockedTimelockAccount: return 2
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Code_Account_V1_IsCodeAccountResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Account_V1_IsCodeAccountResponse.Result] = [
    .ok,
    .notFound,
    .unlockedTimelockAccount,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Account_V1_GetTokenAccountInfosRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The owner account, which can also be thought of as a parent account for this
  /// RPC that links to one or more token accounts.
  public var owner: Code_Common_V1_SolanaAccountId {
    get {return _owner ?? Code_Common_V1_SolanaAccountId()}
    set {_owner = newValue}
  }
  /// Returns true if `owner` has been explicitly set.
  public var hasOwner: Bool {return self._owner != nil}
  /// Clears the value of `owner`. Subsequent reads from it will return its default value.
  public mutating func clearOwner() {self._owner = nil}

  /// The signature is of serialize(GetTokenAccountInfosRequest) without this field set
  /// using the private key of the owner account. This provides an authentication
  /// mechanism to the RPC.
  public var signature: Code_Common_V1_Signature {
    get {return _signature ?? Code_Common_V1_Signature()}
    set {_signature = newValue}
  }
  /// Returns true if `signature` has been explicitly set.
  public var hasSignature: Bool {return self._signature != nil}
  /// Clears the value of `signature`. Subsequent reads from it will return its default value.
  public mutating func clearSignature() {self._signature = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _owner: Code_Common_V1_SolanaAccountId? = nil
  fileprivate var _signature: Code_Common_V1_Signature? = nil
}

public struct Code_Account_V1_GetTokenAccountInfosResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Account_V1_GetTokenAccountInfosResponse.Result = .ok

  public var tokenAccountInfos: Dictionary<String,Code_Account_V1_TokenAccountInfo> = [:]

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ok // = 0
    case notFound // = 1
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      case 1: self = .notFound
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .notFound: return 1
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Code_Account_V1_GetTokenAccountInfosResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Account_V1_GetTokenAccountInfosResponse.Result] = [
    .ok,
    .notFound,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Account_V1_TokenAccountInfo {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The token account's address
  public var address: Code_Common_V1_SolanaAccountId {
    get {return _address ?? Code_Common_V1_SolanaAccountId()}
    set {_address = newValue}
  }
  /// Returns true if `address` has been explicitly set.
  public var hasAddress: Bool {return self._address != nil}
  /// Clears the value of `address`. Subsequent reads from it will return its default value.
  public mutating func clearAddress() {self._address = nil}

  /// The owner of the token account, which can also be thought of as a parent
  /// account that links to one or more token accounts. This is provided when
  /// available.
  public var owner: Code_Common_V1_SolanaAccountId {
    get {return _owner ?? Code_Common_V1_SolanaAccountId()}
    set {_owner = newValue}
  }
  /// Returns true if `owner` has been explicitly set.
  public var hasOwner: Bool {return self._owner != nil}
  /// Clears the value of `owner`. Subsequent reads from it will return its default value.
  public mutating func clearOwner() {self._owner = nil}

  /// The token account's authority, which has access to moving funds for the
  /// account. This can be the owner account under certain circumstances (eg.
  /// ATA, primary account). This is provided when available.
  public var authority: Code_Common_V1_SolanaAccountId {
    get {return _authority ?? Code_Common_V1_SolanaAccountId()}
    set {_authority = newValue}
  }
  /// Returns true if `authority` has been explicitly set.
  public var hasAuthority: Bool {return self._authority != nil}
  /// Clears the value of `authority`. Subsequent reads from it will return its default value.
  public mutating func clearAuthority() {self._authority = nil}

  /// The type of token account, which infers its intended use.
  public var accountType: Code_Common_V1_AccountType = .unknown

  /// The account's derivation index for applicable account types. When this field
  /// doesn't apply, a zero value is provided.
  public var index: UInt64 = 0

  /// The source of truth for the balance calculation.
  public var balanceSource: Code_Account_V1_TokenAccountInfo.BalanceSource = .unknown

  /// The Kin balance in quarks, as observed by Code. This may not reflect the
  /// value on the blockchain and could be non-zero even if the account hasn't
  /// been created. Use balance_source to determine how this value was calculated.
  public var balance: UInt64 = 0

  /// The state of the account as it pertains to Code's ability to manage funds.
  public var managementState: Code_Account_V1_TokenAccountInfo.ManagementState = .unknown

  /// The state of the account on the blockchain.
  public var blockchainState: Code_Account_V1_TokenAccountInfo.BlockchainState = .unknown

  /// For temporary incoming accounts only. Flag indicates whether client must
  /// actively try rotating it by issuing a ReceivePayments intent. In general,
  /// clients should wait as long as possible until this flag is true or requiring
  /// the funds to send their next payment.
  public var mustRotate: Bool = false

  /// Whether an account is claimed. This only applies to relevant account types
  /// (eg. REMOTE_SEND_GIFT_CARD).
  public var claimState: Code_Account_V1_TokenAccountInfo.ClaimState = .unknown

  /// For account types used as an intermediary for sending money between two
  /// users (eg. REMOTE_SEND_GIFT_CARD), this represents the original exchange
  /// data used to fund the account. Over time, this value will become stale:
  ///  1. Exchange rates will fluctuate, so the total fiat amount will differ.
  ///  2. External entities can deposit additional funds into the account, so
  ///     the balance, in quarks, may be greater than the original quark value.
  ///  3. The balance could have been received, so the total balance can show
  ///     as zero.
  public var originalExchangeData: Code_Transaction_V2_ExchangeData {
    get {return _originalExchangeData ?? Code_Transaction_V2_ExchangeData()}
    set {_originalExchangeData = newValue}
  }
  /// Returns true if `originalExchangeData` has been explicitly set.
  public var hasOriginalExchangeData: Bool {return self._originalExchangeData != nil}
  /// Clears the value of `originalExchangeData`. Subsequent reads from it will return its default value.
  public mutating func clearOriginalExchangeData() {self._originalExchangeData = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum BalanceSource: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    /// The account's balance could not be determined. This may be returned when
    /// the data source is unstable and a reliable balance cannot be determined.
    case unknown // = 0

    /// The account's balance was fetched directly from a finalized state on the
    /// blockchain.
    case blockchain // = 1

    /// The account's balance was calculated using cached values in Code. Accuracy
    /// is only guaranteed when management_state is LOCKED.
    case cache // = 2
    case UNRECOGNIZED(Int)

    public init() {
      self = .unknown
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .blockchain
      case 2: self = .cache
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .blockchain: return 1
      case .cache: return 2
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public enum ManagementState: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    /// The state of the account is unknown. This may be returned when the
    /// data source is unstable and a reliable state cannot be determined.
    case unknown // = 0

    /// Code does not maintain a management state and won't move funds for this
    /// account.
    case none // = 1

    /// The account is in the process of transitioning to the LOCKED state.
    case locking // = 2

    /// The account's funds are locked and Code has co-signing authority.
    case locked // = 3

    /// The account is in the process of transitioning to the UNLOCKED state.
    case unlocking // = 4

    /// The account's funds are unlocked and Code no longer has co-signing
    /// authority. The account must transition to the LOCKED state to have
    /// management capabilities.
    case unlocked // = 5

    /// The account is in the process of transitioning to the CLOSED state.
    case closing // = 6

    /// The account has been closed and doesn't exist on the blockchain.
    /// Subsequently, it also has a zero balance.
    case closed // = 7
    case UNRECOGNIZED(Int)

    public init() {
      self = .unknown
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .none
      case 2: self = .locking
      case 3: self = .locked
      case 4: self = .unlocking
      case 5: self = .unlocked
      case 6: self = .closing
      case 7: self = .closed
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .none: return 1
      case .locking: return 2
      case .locked: return 3
      case .unlocking: return 4
      case .unlocked: return 5
      case .closing: return 6
      case .closed: return 7
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public enum BlockchainState: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    /// The state of the account is unknown. This may be returned when the
    /// data source is unstable and a reliable state cannot be determined.
    case unknown // = 0

    /// The account does not exist on the blockchain.
    case doesNotExist // = 1

    /// The account is created and exists on the blockchain.
    case exists // = 2
    case UNRECOGNIZED(Int)

    public init() {
      self = .unknown
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .doesNotExist
      case 2: self = .exists
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .doesNotExist: return 1
      case .exists: return 2
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public enum ClaimState: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    /// The account doesn't have a concept of being claimed, or the state
    /// could not be fetched by server.
    case unknown // = 0

    /// The account has not yet been claimed.
    case notClaimed // = 1

    /// The account is claimed. Attempting to claim it will fail.
    case claimed // = 2

    /// The account hasn't been claimed, but is expired. Funds will move
    /// back to the issuer. Attempting to claim it will fail.
    case expired // = 3
    case UNRECOGNIZED(Int)

    public init() {
      self = .unknown
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .notClaimed
      case 2: self = .claimed
      case 3: self = .expired
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .notClaimed: return 1
      case .claimed: return 2
      case .expired: return 3
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}

  fileprivate var _address: Code_Common_V1_SolanaAccountId? = nil
  fileprivate var _owner: Code_Common_V1_SolanaAccountId? = nil
  fileprivate var _authority: Code_Common_V1_SolanaAccountId? = nil
  fileprivate var _originalExchangeData: Code_Transaction_V2_ExchangeData? = nil
}

#if swift(>=4.2)

extension Code_Account_V1_TokenAccountInfo.BalanceSource: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Account_V1_TokenAccountInfo.BalanceSource] = [
    .unknown,
    .blockchain,
    .cache,
  ]
}

extension Code_Account_V1_TokenAccountInfo.ManagementState: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Account_V1_TokenAccountInfo.ManagementState] = [
    .unknown,
    .none,
    .locking,
    .locked,
    .unlocking,
    .unlocked,
    .closing,
    .closed,
  ]
}

extension Code_Account_V1_TokenAccountInfo.BlockchainState: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Account_V1_TokenAccountInfo.BlockchainState] = [
    .unknown,
    .doesNotExist,
    .exists,
  ]
}

extension Code_Account_V1_TokenAccountInfo.ClaimState: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Account_V1_TokenAccountInfo.ClaimState] = [
    .unknown,
    .notClaimed,
    .claimed,
    .expired,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Code_Account_V1_IsCodeAccountRequest: @unchecked Sendable {}
extension Code_Account_V1_IsCodeAccountResponse: @unchecked Sendable {}
extension Code_Account_V1_IsCodeAccountResponse.Result: @unchecked Sendable {}
extension Code_Account_V1_GetTokenAccountInfosRequest: @unchecked Sendable {}
extension Code_Account_V1_GetTokenAccountInfosResponse: @unchecked Sendable {}
extension Code_Account_V1_GetTokenAccountInfosResponse.Result: @unchecked Sendable {}
extension Code_Account_V1_TokenAccountInfo: @unchecked Sendable {}
extension Code_Account_V1_TokenAccountInfo.BalanceSource: @unchecked Sendable {}
extension Code_Account_V1_TokenAccountInfo.ManagementState: @unchecked Sendable {}
extension Code_Account_V1_TokenAccountInfo.BlockchainState: @unchecked Sendable {}
extension Code_Account_V1_TokenAccountInfo.ClaimState: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "code.account.v1"

extension Code_Account_V1_IsCodeAccountRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".IsCodeAccountRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "owner"),
    2: .same(proto: "signature"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._owner) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._signature) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._owner {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._signature {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Account_V1_IsCodeAccountRequest, rhs: Code_Account_V1_IsCodeAccountRequest) -> Bool {
    if lhs._owner != rhs._owner {return false}
    if lhs._signature != rhs._signature {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Account_V1_IsCodeAccountResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".IsCodeAccountResponse"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "result"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.result) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.result != .ok {
      try visitor.visitSingularEnumField(value: self.result, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Account_V1_IsCodeAccountResponse, rhs: Code_Account_V1_IsCodeAccountResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Account_V1_IsCodeAccountResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
    1: .same(proto: "NOT_FOUND"),
    2: .same(proto: "UNLOCKED_TIMELOCK_ACCOUNT"),
  ]
}

extension Code_Account_V1_GetTokenAccountInfosRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".GetTokenAccountInfosRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "owner"),
    2: .same(proto: "signature"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._owner) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._signature) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._owner {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._signature {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Account_V1_GetTokenAccountInfosRequest, rhs: Code_Account_V1_GetTokenAccountInfosRequest) -> Bool {
    if lhs._owner != rhs._owner {return false}
    if lhs._signature != rhs._signature {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Account_V1_GetTokenAccountInfosResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".GetTokenAccountInfosResponse"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "result"),
    2: .standard(proto: "token_account_infos"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.result) }()
      case 2: try { try decoder.decodeMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufString,Code_Account_V1_TokenAccountInfo>.self, value: &self.tokenAccountInfos) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.result != .ok {
      try visitor.visitSingularEnumField(value: self.result, fieldNumber: 1)
    }
    if !self.tokenAccountInfos.isEmpty {
      try visitor.visitMapField(fieldType: SwiftProtobuf._ProtobufMessageMap<SwiftProtobuf.ProtobufString,Code_Account_V1_TokenAccountInfo>.self, value: self.tokenAccountInfos, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Account_V1_GetTokenAccountInfosResponse, rhs: Code_Account_V1_GetTokenAccountInfosResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs.tokenAccountInfos != rhs.tokenAccountInfos {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Account_V1_GetTokenAccountInfosResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
    1: .same(proto: "NOT_FOUND"),
  ]
}

extension Code_Account_V1_TokenAccountInfo: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".TokenAccountInfo"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "address"),
    2: .same(proto: "owner"),
    3: .same(proto: "authority"),
    4: .standard(proto: "account_type"),
    5: .same(proto: "index"),
    6: .standard(proto: "balance_source"),
    7: .same(proto: "balance"),
    8: .standard(proto: "management_state"),
    9: .standard(proto: "blockchain_state"),
    10: .standard(proto: "must_rotate"),
    11: .standard(proto: "claim_state"),
    12: .standard(proto: "original_exchange_data"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._address) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._owner) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._authority) }()
      case 4: try { try decoder.decodeSingularEnumField(value: &self.accountType) }()
      case 5: try { try decoder.decodeSingularUInt64Field(value: &self.index) }()
      case 6: try { try decoder.decodeSingularEnumField(value: &self.balanceSource) }()
      case 7: try { try decoder.decodeSingularUInt64Field(value: &self.balance) }()
      case 8: try { try decoder.decodeSingularEnumField(value: &self.managementState) }()
      case 9: try { try decoder.decodeSingularEnumField(value: &self.blockchainState) }()
      case 10: try { try decoder.decodeSingularBoolField(value: &self.mustRotate) }()
      case 11: try { try decoder.decodeSingularEnumField(value: &self.claimState) }()
      case 12: try { try decoder.decodeSingularMessageField(value: &self._originalExchangeData) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._address {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._owner {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try { if let v = self._authority {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    if self.accountType != .unknown {
      try visitor.visitSingularEnumField(value: self.accountType, fieldNumber: 4)
    }
    if self.index != 0 {
      try visitor.visitSingularUInt64Field(value: self.index, fieldNumber: 5)
    }
    if self.balanceSource != .unknown {
      try visitor.visitSingularEnumField(value: self.balanceSource, fieldNumber: 6)
    }
    if self.balance != 0 {
      try visitor.visitSingularUInt64Field(value: self.balance, fieldNumber: 7)
    }
    if self.managementState != .unknown {
      try visitor.visitSingularEnumField(value: self.managementState, fieldNumber: 8)
    }
    if self.blockchainState != .unknown {
      try visitor.visitSingularEnumField(value: self.blockchainState, fieldNumber: 9)
    }
    if self.mustRotate != false {
      try visitor.visitSingularBoolField(value: self.mustRotate, fieldNumber: 10)
    }
    if self.claimState != .unknown {
      try visitor.visitSingularEnumField(value: self.claimState, fieldNumber: 11)
    }
    try { if let v = self._originalExchangeData {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 12)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Account_V1_TokenAccountInfo, rhs: Code_Account_V1_TokenAccountInfo) -> Bool {
    if lhs._address != rhs._address {return false}
    if lhs._owner != rhs._owner {return false}
    if lhs._authority != rhs._authority {return false}
    if lhs.accountType != rhs.accountType {return false}
    if lhs.index != rhs.index {return false}
    if lhs.balanceSource != rhs.balanceSource {return false}
    if lhs.balance != rhs.balance {return false}
    if lhs.managementState != rhs.managementState {return false}
    if lhs.blockchainState != rhs.blockchainState {return false}
    if lhs.mustRotate != rhs.mustRotate {return false}
    if lhs.claimState != rhs.claimState {return false}
    if lhs._originalExchangeData != rhs._originalExchangeData {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Account_V1_TokenAccountInfo.BalanceSource: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "BALANCE_SOURCE_UNKNOWN"),
    1: .same(proto: "BALANCE_SOURCE_BLOCKCHAIN"),
    2: .same(proto: "BALANCE_SOURCE_CACHE"),
  ]
}

extension Code_Account_V1_TokenAccountInfo.ManagementState: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "MANAGEMENT_STATE_UNKNOWN"),
    1: .same(proto: "MANAGEMENT_STATE_NONE"),
    2: .same(proto: "MANAGEMENT_STATE_LOCKING"),
    3: .same(proto: "MANAGEMENT_STATE_LOCKED"),
    4: .same(proto: "MANAGEMENT_STATE_UNLOCKING"),
    5: .same(proto: "MANAGEMENT_STATE_UNLOCKED"),
    6: .same(proto: "MANAGEMENT_STATE_CLOSING"),
    7: .same(proto: "MANAGEMENT_STATE_CLOSED"),
  ]
}

extension Code_Account_V1_TokenAccountInfo.BlockchainState: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "BLOCKCHAIN_STATE_UNKNOWN"),
    1: .same(proto: "BLOCKCHAIN_STATE_DOES_NOT_EXIST"),
    2: .same(proto: "BLOCKCHAIN_STATE_EXISTS"),
  ]
}

extension Code_Account_V1_TokenAccountInfo.ClaimState: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "CLAIM_STATE_UNKNOWN"),
    1: .same(proto: "CLAIM_STATE_NOT_CLAIMED"),
    2: .same(proto: "CLAIM_STATE_CLAIMED"),
    3: .same(proto: "CLAIM_STATE_EXPIRED"),
  ]
}
