// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: invite/v2/invite_service.proto
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

public enum Code_Invite_V2_InvitationStatus: SwiftProtobuf.Enum {
  public typealias RawValue = Int

  /// The phone number has never been invited.
  case notInvited // = 0

  /// The phone number has been invited at least once.
  case invited // = 1

  /// The phone number has been invited and used the app at least once via a
  /// phone verified account creation or login.
  case registered // = 2

  /// The phone number was invited, but revoked at a later time.
  case revoked // = 3
  case UNRECOGNIZED(Int)

  public init() {
    self = .notInvited
  }

  public init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .notInvited
    case 1: self = .invited
    case 2: self = .registered
    case 3: self = .revoked
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  public var rawValue: Int {
    switch self {
    case .notInvited: return 0
    case .invited: return 1
    case .registered: return 2
    case .revoked: return 3
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Code_Invite_V2_InvitationStatus: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Invite_V2_InvitationStatus] = [
    .notInvited,
    .invited,
    .registered,
    .revoked,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Invite_V2_GetInviteCountRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The user to query for their invite count
  public var userID: Code_Common_V1_UserId {
    get {return _userID ?? Code_Common_V1_UserId()}
    set {_userID = newValue}
  }
  /// Returns true if `userID` has been explicitly set.
  public var hasUserID: Bool {return self._userID != nil}
  /// Clears the value of `userID`. Subsequent reads from it will return its default value.
  public mutating func clearUserID() {self._userID = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _userID: Code_Common_V1_UserId? = nil
}

public struct Code_Invite_V2_GetInviteCountResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Invite_V2_GetInviteCountResponse.Result = .ok

  /// The number of invites the user is allowed to issue.
  public var inviteCount: UInt32 = 0

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ok // = 0
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Code_Invite_V2_GetInviteCountResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Invite_V2_GetInviteCountResponse.Result] = [
    .ok,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Invite_V2_InvitePhoneNumberRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The source for the invite. One of these values must be present
  public var source: Code_Invite_V2_InvitePhoneNumberRequest.OneOf_Source? = nil

  public var user: Code_Common_V1_UserId {
    get {
      if case .user(let v)? = source {return v}
      return Code_Common_V1_UserId()
    }
    set {source = .user(newValue)}
  }

  public var inviteCode: Code_Invite_V2_InviteCode {
    get {
      if case .inviteCode(let v)? = source {return v}
      return Code_Invite_V2_InviteCode()
    }
    set {source = .inviteCode(newValue)}
  }

  /// The phone number receiving the invite.
  public var receiver: Code_Common_V1_PhoneNumber {
    get {return _receiver ?? Code_Common_V1_PhoneNumber()}
    set {_receiver = newValue}
  }
  /// Returns true if `receiver` has been explicitly set.
  public var hasReceiver: Bool {return self._receiver != nil}
  /// Clears the value of `receiver`. Subsequent reads from it will return its default value.
  public mutating func clearReceiver() {self._receiver = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  /// The source for the invite. One of these values must be present
  public enum OneOf_Source: Equatable {
    case user(Code_Common_V1_UserId)
    case inviteCode(Code_Invite_V2_InviteCode)

  #if !swift(>=4.1)
    public static func ==(lhs: Code_Invite_V2_InvitePhoneNumberRequest.OneOf_Source, rhs: Code_Invite_V2_InvitePhoneNumberRequest.OneOf_Source) -> Bool {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch (lhs, rhs) {
      case (.user, .user): return {
        guard case .user(let l) = lhs, case .user(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      case (.inviteCode, .inviteCode): return {
        guard case .inviteCode(let l) = lhs, case .inviteCode(let r) = rhs else { preconditionFailure() }
        return l == r
      }()
      default: return false
      }
    }
  #endif
  }

  public init() {}

  fileprivate var _receiver: Code_Common_V1_PhoneNumber? = nil
}

public struct Code_Invite_V2_InvitePhoneNumberResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Invite_V2_InvitePhoneNumberResponse.Result = .ok

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ok // = 0

    /// The source exceeded their invite count and is restricted from issuing
    /// further invites.
    case inviteCountExceeded // = 1

    /// The receiver phone number has already been invited. Regardless of who
    /// invited it, the source's invite count is not decremented when this is
    /// returned.
    case alreadyInvited // = 2

    /// The source  user has not been invited.
    case userNotInvited // = 3

    /// The receiver phone number failed validation.
    case invalidReceiverPhoneNumber // = 4

    /// The invite code doesn't exist.
    case inviteCodeNotFound // = 5

    /// The invite code has been revoked.
    case inviteCodeRevoked // = 6

    /// The invite code has expired.
    case inviteCodeExpired // = 7
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      case 1: self = .inviteCountExceeded
      case 2: self = .alreadyInvited
      case 3: self = .userNotInvited
      case 4: self = .invalidReceiverPhoneNumber
      case 5: self = .inviteCodeNotFound
      case 6: self = .inviteCodeRevoked
      case 7: self = .inviteCodeExpired
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .inviteCountExceeded: return 1
      case .alreadyInvited: return 2
      case .userNotInvited: return 3
      case .invalidReceiverPhoneNumber: return 4
      case .inviteCodeNotFound: return 5
      case .inviteCodeRevoked: return 6
      case .inviteCodeExpired: return 7
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Code_Invite_V2_InvitePhoneNumberResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Invite_V2_InvitePhoneNumberResponse.Result] = [
    .ok,
    .inviteCountExceeded,
    .alreadyInvited,
    .userNotInvited,
    .invalidReceiverPhoneNumber,
    .inviteCodeNotFound,
    .inviteCodeRevoked,
    .inviteCodeExpired,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Invite_V2_GetInvitationStatusRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The user being queried for their invitation status.
  public var userID: Code_Common_V1_UserId {
    get {return _userID ?? Code_Common_V1_UserId()}
    set {_userID = newValue}
  }
  /// Returns true if `userID` has been explicitly set.
  public var hasUserID: Bool {return self._userID != nil}
  /// Clears the value of `userID`. Subsequent reads from it will return its default value.
  public mutating func clearUserID() {self._userID = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _userID: Code_Common_V1_UserId? = nil
}

public struct Code_Invite_V2_GetInvitationStatusResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Invite_V2_GetInvitationStatusResponse.Result = .ok

  /// The user's invitation status
  public var status: Code_Invite_V2_InvitationStatus = .notInvited

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ok // = 0
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Code_Invite_V2_GetInvitationStatusResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Invite_V2_GetInvitationStatusResponse.Result] = [
    .ok,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Invite_V2_InviteCode {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Regex for invite codes
  public var value: String = String()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

public struct Code_Invite_V2_PageToken {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var value: Data = Data()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Code_Invite_V2_InvitationStatus: @unchecked Sendable {}
extension Code_Invite_V2_GetInviteCountRequest: @unchecked Sendable {}
extension Code_Invite_V2_GetInviteCountResponse: @unchecked Sendable {}
extension Code_Invite_V2_GetInviteCountResponse.Result: @unchecked Sendable {}
extension Code_Invite_V2_InvitePhoneNumberRequest: @unchecked Sendable {}
extension Code_Invite_V2_InvitePhoneNumberRequest.OneOf_Source: @unchecked Sendable {}
extension Code_Invite_V2_InvitePhoneNumberResponse: @unchecked Sendable {}
extension Code_Invite_V2_InvitePhoneNumberResponse.Result: @unchecked Sendable {}
extension Code_Invite_V2_GetInvitationStatusRequest: @unchecked Sendable {}
extension Code_Invite_V2_GetInvitationStatusResponse: @unchecked Sendable {}
extension Code_Invite_V2_GetInvitationStatusResponse.Result: @unchecked Sendable {}
extension Code_Invite_V2_InviteCode: @unchecked Sendable {}
extension Code_Invite_V2_PageToken: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "code.invite.v2"

extension Code_Invite_V2_InvitationStatus: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "NOT_INVITED"),
    1: .same(proto: "INVITED"),
    2: .same(proto: "REGISTERED"),
    3: .same(proto: "REVOKED"),
  ]
}

extension Code_Invite_V2_GetInviteCountRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".GetInviteCountRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "user_id"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._userID) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._userID {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Invite_V2_GetInviteCountRequest, rhs: Code_Invite_V2_GetInviteCountRequest) -> Bool {
    if lhs._userID != rhs._userID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Invite_V2_GetInviteCountResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".GetInviteCountResponse"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "result"),
    2: .standard(proto: "invite_count"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.result) }()
      case 2: try { try decoder.decodeSingularUInt32Field(value: &self.inviteCount) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.result != .ok {
      try visitor.visitSingularEnumField(value: self.result, fieldNumber: 1)
    }
    if self.inviteCount != 0 {
      try visitor.visitSingularUInt32Field(value: self.inviteCount, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Invite_V2_GetInviteCountResponse, rhs: Code_Invite_V2_GetInviteCountResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs.inviteCount != rhs.inviteCount {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Invite_V2_GetInviteCountResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
  ]
}

extension Code_Invite_V2_InvitePhoneNumberRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".InvitePhoneNumberRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "user"),
    3: .standard(proto: "invite_code"),
    2: .same(proto: "receiver"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try {
        var v: Code_Common_V1_UserId?
        var hadOneofValue = false
        if let current = self.source {
          hadOneofValue = true
          if case .user(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.source = .user(v)
        }
      }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._receiver) }()
      case 3: try {
        var v: Code_Invite_V2_InviteCode?
        var hadOneofValue = false
        if let current = self.source {
          hadOneofValue = true
          if case .inviteCode(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.source = .inviteCode(v)
        }
      }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if case .user(let v)? = self.source {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._receiver {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try { if case .inviteCode(let v)? = self.source {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Invite_V2_InvitePhoneNumberRequest, rhs: Code_Invite_V2_InvitePhoneNumberRequest) -> Bool {
    if lhs.source != rhs.source {return false}
    if lhs._receiver != rhs._receiver {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Invite_V2_InvitePhoneNumberResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".InvitePhoneNumberResponse"
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

  public static func ==(lhs: Code_Invite_V2_InvitePhoneNumberResponse, rhs: Code_Invite_V2_InvitePhoneNumberResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Invite_V2_InvitePhoneNumberResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
    1: .same(proto: "INVITE_COUNT_EXCEEDED"),
    2: .same(proto: "ALREADY_INVITED"),
    3: .same(proto: "USER_NOT_INVITED"),
    4: .same(proto: "INVALID_RECEIVER_PHONE_NUMBER"),
    5: .same(proto: "INVITE_CODE_NOT_FOUND"),
    6: .same(proto: "INVITE_CODE_REVOKED"),
    7: .same(proto: "INVITE_CODE_EXPIRED"),
  ]
}

extension Code_Invite_V2_GetInvitationStatusRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".GetInvitationStatusRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "user_id"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._userID) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._userID {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Invite_V2_GetInvitationStatusRequest, rhs: Code_Invite_V2_GetInvitationStatusRequest) -> Bool {
    if lhs._userID != rhs._userID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Invite_V2_GetInvitationStatusResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".GetInvitationStatusResponse"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "result"),
    2: .same(proto: "status"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.result) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self.status) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.result != .ok {
      try visitor.visitSingularEnumField(value: self.result, fieldNumber: 1)
    }
    if self.status != .notInvited {
      try visitor.visitSingularEnumField(value: self.status, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Invite_V2_GetInvitationStatusResponse, rhs: Code_Invite_V2_GetInvitationStatusResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs.status != rhs.status {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Invite_V2_GetInvitationStatusResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
  ]
}

extension Code_Invite_V2_InviteCode: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".InviteCode"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "value"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularStringField(value: &self.value) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.value.isEmpty {
      try visitor.visitSingularStringField(value: self.value, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Invite_V2_InviteCode, rhs: Code_Invite_V2_InviteCode) -> Bool {
    if lhs.value != rhs.value {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Invite_V2_PageToken: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".PageToken"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "value"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.value) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.value.isEmpty {
      try visitor.visitSingularBytesField(value: self.value, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Invite_V2_PageToken, rhs: Code_Invite_V2_PageToken) -> Bool {
    if lhs.value != rhs.value {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
