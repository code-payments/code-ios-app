// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: phone/v1/phone_verification_service.proto
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

public struct Code_Phone_V1_SendVerificationCodeRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The phone number to send a verification code over SMS to.
  public var phoneNumber: Code_Common_V1_PhoneNumber {
    get {return _phoneNumber ?? Code_Common_V1_PhoneNumber()}
    set {_phoneNumber = newValue}
  }
  /// Returns true if `phoneNumber` has been explicitly set.
  public var hasPhoneNumber: Bool {return self._phoneNumber != nil}
  /// Clears the value of `phoneNumber`. Subsequent reads from it will return its default value.
  public mutating func clearPhoneNumber() {self._phoneNumber = nil}

  /// Device token for antispam measures against fake devices
  public var deviceToken: Code_Common_V1_DeviceToken {
    get {return _deviceToken ?? Code_Common_V1_DeviceToken()}
    set {_deviceToken = newValue}
  }
  /// Returns true if `deviceToken` has been explicitly set.
  public var hasDeviceToken: Bool {return self._deviceToken != nil}
  /// Clears the value of `deviceToken`. Subsequent reads from it will return its default value.
  public mutating func clearDeviceToken() {self._deviceToken = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _phoneNumber: Code_Common_V1_PhoneNumber? = nil
  fileprivate var _deviceToken: Code_Common_V1_DeviceToken? = nil
}

public struct Code_Phone_V1_SendVerificationCodeResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Phone_V1_SendVerificationCodeResponse.Result = .ok

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ok // = 0

    /// The phone number is not invited and cannot use Code. The SMS will not
    /// be sent until the user is invited. This result is only valid during
    /// the invitation stage of the application and won't apply after general
    /// public release.
    case notInvited // = 1

    /// SMS is rate limited (eg. by IP, phone number, etc) and was not sent.
    /// These will be set generously such that real users won't actually hit
    /// the limits.
    case rateLimited // = 2

    /// The phone number is not real because it fails Twilio lookup.
    case invalidPhoneNumber // = 3

    /// The phone number is valid, but it maps to an unsupported type of phone
    /// like a landline or eSIM.
    case unsupportedPhoneType // = 4

    /// The country associated with the phone number is not supported (eg. it
    /// is on the sanctioned list).
    case unsupportedCountry // = 5

    /// The device is not supported (eg. it fails device attestation checks)
    case unsupportedDevice // = 6
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      case 1: self = .notInvited
      case 2: self = .rateLimited
      case 3: self = .invalidPhoneNumber
      case 4: self = .unsupportedPhoneType
      case 5: self = .unsupportedCountry
      case 6: self = .unsupportedDevice
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .notInvited: return 1
      case .rateLimited: return 2
      case .invalidPhoneNumber: return 3
      case .unsupportedPhoneType: return 4
      case .unsupportedCountry: return 5
      case .unsupportedDevice: return 6
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Code_Phone_V1_SendVerificationCodeResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Phone_V1_SendVerificationCodeResponse.Result] = [
    .ok,
    .notInvited,
    .rateLimited,
    .invalidPhoneNumber,
    .unsupportedPhoneType,
    .unsupportedCountry,
    .unsupportedDevice,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Phone_V1_CheckVerificationCodeRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The phone number being verified.
  public var phoneNumber: Code_Common_V1_PhoneNumber {
    get {return _phoneNumber ?? Code_Common_V1_PhoneNumber()}
    set {_phoneNumber = newValue}
  }
  /// Returns true if `phoneNumber` has been explicitly set.
  public var hasPhoneNumber: Bool {return self._phoneNumber != nil}
  /// Clears the value of `phoneNumber`. Subsequent reads from it will return its default value.
  public mutating func clearPhoneNumber() {self._phoneNumber = nil}

  /// The verification code received via SMS.
  public var code: Code_Phone_V1_VerificationCode {
    get {return _code ?? Code_Phone_V1_VerificationCode()}
    set {_code = newValue}
  }
  /// Returns true if `code` has been explicitly set.
  public var hasCode: Bool {return self._code != nil}
  /// Clears the value of `code`. Subsequent reads from it will return its default value.
  public mutating func clearCode() {self._code = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _phoneNumber: Code_Common_V1_PhoneNumber? = nil
  fileprivate var _code: Code_Phone_V1_VerificationCode? = nil
}

public struct Code_Phone_V1_CheckVerificationCodeResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Phone_V1_CheckVerificationCodeResponse.Result = .ok

  /// The token used to associate an owner account to a user using the verified
  /// phone number.
  public var linkingToken: Code_Phone_V1_PhoneLinkingToken {
    get {return _linkingToken ?? Code_Phone_V1_PhoneLinkingToken()}
    set {_linkingToken = newValue}
  }
  /// Returns true if `linkingToken` has been explicitly set.
  public var hasLinkingToken: Bool {return self._linkingToken != nil}
  /// Clears the value of `linkingToken`. Subsequent reads from it will return its default value.
  public mutating func clearLinkingToken() {self._linkingToken = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ok // = 0

    /// The provided verification code is invalid. The user may retry
    /// enterring the code if this is received. When max attempts are
    /// received, NO_VERIFICATION will be returned.
    case invalidCode // = 1

    /// There is no verification in progress for the phone number. Several
    /// reasons this can occur include a verification being expired or having
    /// reached a maximum check threshold. The client must initiate a new
    /// verification using SendVerificationCode.
    case noVerification // = 2

    /// The call is rate limited (eg. by IP, phone number, etc). The code is
    /// not verified.
    case rateLimited // = 3
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      case 1: self = .invalidCode
      case 2: self = .noVerification
      case 3: self = .rateLimited
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .invalidCode: return 1
      case .noVerification: return 2
      case .rateLimited: return 3
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}

  fileprivate var _linkingToken: Code_Phone_V1_PhoneLinkingToken? = nil
}

#if swift(>=4.2)

extension Code_Phone_V1_CheckVerificationCodeResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Phone_V1_CheckVerificationCodeResponse.Result] = [
    .ok,
    .invalidCode,
    .noVerification,
    .rateLimited,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Phone_V1_GetAssociatedPhoneNumberRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The public key of the owner account that is being queried for a linked
  /// phone number.
  public var ownerAccountID: Code_Common_V1_SolanaAccountId {
    get {return _ownerAccountID ?? Code_Common_V1_SolanaAccountId()}
    set {_ownerAccountID = newValue}
  }
  /// Returns true if `ownerAccountID` has been explicitly set.
  public var hasOwnerAccountID: Bool {return self._ownerAccountID != nil}
  /// Clears the value of `ownerAccountID`. Subsequent reads from it will return its default value.
  public mutating func clearOwnerAccountID() {self._ownerAccountID = nil}

  /// The signature is of serialize(GetAssociatedPhoneNumberRequest) without
  /// this field set using the private key of owner_account_id. This provides
  /// an authentication mechanism to the RPC.
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

  fileprivate var _ownerAccountID: Code_Common_V1_SolanaAccountId? = nil
  fileprivate var _signature: Code_Common_V1_Signature? = nil
}

public struct Code_Phone_V1_GetAssociatedPhoneNumberResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Phone_V1_GetAssociatedPhoneNumberResponse.Result = .ok

  /// The latest phone number associated with the owner account.
  public var phoneNumber: Code_Common_V1_PhoneNumber {
    get {return _phoneNumber ?? Code_Common_V1_PhoneNumber()}
    set {_phoneNumber = newValue}
  }
  /// Returns true if `phoneNumber` has been explicitly set.
  public var hasPhoneNumber: Bool {return self._phoneNumber != nil}
  /// Clears the value of `phoneNumber`. Subsequent reads from it will return its default value.
  public mutating func clearPhoneNumber() {self._phoneNumber = nil}

  /// State that determines whether a phone number is linked to the owner
  /// account. A phone number is linked if we can treat it as an alias.
  /// This is notably different from association, which answers the question
  /// of whether the number was linked at any point in time.
  public var isLinked: Bool = false

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ok // = 0

    /// A phone number is not associated with the provided owner account.
    case notFound // = 1

    /// The phone number exists, but is no longer invited
    case notInvited // = 2

    /// The phone number exists, but at least one timelock account is unlocked
    case unlockedTimelockAccount // = 3
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      case 1: self = .notFound
      case 2: self = .notInvited
      case 3: self = .unlockedTimelockAccount
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .notFound: return 1
      case .notInvited: return 2
      case .unlockedTimelockAccount: return 3
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}

  fileprivate var _phoneNumber: Code_Common_V1_PhoneNumber? = nil
}

#if swift(>=4.2)

extension Code_Phone_V1_GetAssociatedPhoneNumberResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Phone_V1_GetAssociatedPhoneNumberResponse.Result] = [
    .ok,
    .notFound,
    .notInvited,
    .unlockedTimelockAccount,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Phone_V1_VerificationCode {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// A 4-10 digit numerical code.
  public var value: String = String()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

/// A one-time use token that can be provided to the Identity service to link an
/// owner account to a user with the verified phone number. The client should
/// treat this token as opaque.
public struct Code_Phone_V1_PhoneLinkingToken {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The verified phone number.
  public var phoneNumber: Code_Common_V1_PhoneNumber {
    get {return _phoneNumber ?? Code_Common_V1_PhoneNumber()}
    set {_phoneNumber = newValue}
  }
  /// Returns true if `phoneNumber` has been explicitly set.
  public var hasPhoneNumber: Bool {return self._phoneNumber != nil}
  /// Clears the value of `phoneNumber`. Subsequent reads from it will return its default value.
  public mutating func clearPhoneNumber() {self._phoneNumber = nil}

  /// The code that verified the phone number.
  public var code: Code_Phone_V1_VerificationCode {
    get {return _code ?? Code_Phone_V1_VerificationCode()}
    set {_code = newValue}
  }
  /// Returns true if `code` has been explicitly set.
  public var hasCode: Bool {return self._code != nil}
  /// Clears the value of `code`. Subsequent reads from it will return its default value.
  public mutating func clearCode() {self._code = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _phoneNumber: Code_Common_V1_PhoneNumber? = nil
  fileprivate var _code: Code_Phone_V1_VerificationCode? = nil
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Code_Phone_V1_SendVerificationCodeRequest: @unchecked Sendable {}
extension Code_Phone_V1_SendVerificationCodeResponse: @unchecked Sendable {}
extension Code_Phone_V1_SendVerificationCodeResponse.Result: @unchecked Sendable {}
extension Code_Phone_V1_CheckVerificationCodeRequest: @unchecked Sendable {}
extension Code_Phone_V1_CheckVerificationCodeResponse: @unchecked Sendable {}
extension Code_Phone_V1_CheckVerificationCodeResponse.Result: @unchecked Sendable {}
extension Code_Phone_V1_GetAssociatedPhoneNumberRequest: @unchecked Sendable {}
extension Code_Phone_V1_GetAssociatedPhoneNumberResponse: @unchecked Sendable {}
extension Code_Phone_V1_GetAssociatedPhoneNumberResponse.Result: @unchecked Sendable {}
extension Code_Phone_V1_VerificationCode: @unchecked Sendable {}
extension Code_Phone_V1_PhoneLinkingToken: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "code.phone.v1"

extension Code_Phone_V1_SendVerificationCodeRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".SendVerificationCodeRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "phone_number"),
    2: .standard(proto: "device_token"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._phoneNumber) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._deviceToken) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._phoneNumber {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._deviceToken {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Phone_V1_SendVerificationCodeRequest, rhs: Code_Phone_V1_SendVerificationCodeRequest) -> Bool {
    if lhs._phoneNumber != rhs._phoneNumber {return false}
    if lhs._deviceToken != rhs._deviceToken {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Phone_V1_SendVerificationCodeResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".SendVerificationCodeResponse"
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

  public static func ==(lhs: Code_Phone_V1_SendVerificationCodeResponse, rhs: Code_Phone_V1_SendVerificationCodeResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Phone_V1_SendVerificationCodeResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
    1: .same(proto: "NOT_INVITED"),
    2: .same(proto: "RATE_LIMITED"),
    3: .same(proto: "INVALID_PHONE_NUMBER"),
    4: .same(proto: "UNSUPPORTED_PHONE_TYPE"),
    5: .same(proto: "UNSUPPORTED_COUNTRY"),
    6: .same(proto: "UNSUPPORTED_DEVICE"),
  ]
}

extension Code_Phone_V1_CheckVerificationCodeRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".CheckVerificationCodeRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "phone_number"),
    2: .same(proto: "code"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._phoneNumber) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._code) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._phoneNumber {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._code {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Phone_V1_CheckVerificationCodeRequest, rhs: Code_Phone_V1_CheckVerificationCodeRequest) -> Bool {
    if lhs._phoneNumber != rhs._phoneNumber {return false}
    if lhs._code != rhs._code {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Phone_V1_CheckVerificationCodeResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".CheckVerificationCodeResponse"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "result"),
    2: .standard(proto: "linking_token"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.result) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._linkingToken) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if self.result != .ok {
      try visitor.visitSingularEnumField(value: self.result, fieldNumber: 1)
    }
    try { if let v = self._linkingToken {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Phone_V1_CheckVerificationCodeResponse, rhs: Code_Phone_V1_CheckVerificationCodeResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs._linkingToken != rhs._linkingToken {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Phone_V1_CheckVerificationCodeResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
    1: .same(proto: "INVALID_CODE"),
    2: .same(proto: "NO_VERIFICATION"),
    3: .same(proto: "RATE_LIMITED"),
  ]
}

extension Code_Phone_V1_GetAssociatedPhoneNumberRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".GetAssociatedPhoneNumberRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "owner_account_id"),
    2: .same(proto: "signature"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._ownerAccountID) }()
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
    try { if let v = self._ownerAccountID {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._signature {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Phone_V1_GetAssociatedPhoneNumberRequest, rhs: Code_Phone_V1_GetAssociatedPhoneNumberRequest) -> Bool {
    if lhs._ownerAccountID != rhs._ownerAccountID {return false}
    if lhs._signature != rhs._signature {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Phone_V1_GetAssociatedPhoneNumberResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".GetAssociatedPhoneNumberResponse"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "result"),
    2: .standard(proto: "phone_number"),
    3: .standard(proto: "is_linked"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.result) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._phoneNumber) }()
      case 3: try { try decoder.decodeSingularBoolField(value: &self.isLinked) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if self.result != .ok {
      try visitor.visitSingularEnumField(value: self.result, fieldNumber: 1)
    }
    try { if let v = self._phoneNumber {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    if self.isLinked != false {
      try visitor.visitSingularBoolField(value: self.isLinked, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Phone_V1_GetAssociatedPhoneNumberResponse, rhs: Code_Phone_V1_GetAssociatedPhoneNumberResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs._phoneNumber != rhs._phoneNumber {return false}
    if lhs.isLinked != rhs.isLinked {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Phone_V1_GetAssociatedPhoneNumberResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
    1: .same(proto: "NOT_FOUND"),
    2: .same(proto: "NOT_INVITED"),
    3: .same(proto: "UNLOCKED_TIMELOCK_ACCOUNT"),
  ]
}

extension Code_Phone_V1_VerificationCode: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".VerificationCode"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    2: .same(proto: "value"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 2: try { try decoder.decodeSingularStringField(value: &self.value) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.value.isEmpty {
      try visitor.visitSingularStringField(value: self.value, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Phone_V1_VerificationCode, rhs: Code_Phone_V1_VerificationCode) -> Bool {
    if lhs.value != rhs.value {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Phone_V1_PhoneLinkingToken: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".PhoneLinkingToken"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "phone_number"),
    2: .same(proto: "code"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._phoneNumber) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._code) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    try { if let v = self._phoneNumber {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    } }()
    try { if let v = self._code {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Phone_V1_PhoneLinkingToken, rhs: Code_Phone_V1_PhoneLinkingToken) -> Bool {
    if lhs._phoneNumber != rhs._phoneNumber {return false}
    if lhs._code != rhs._code {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
