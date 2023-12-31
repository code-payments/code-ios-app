// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: push/v1/push_service.proto
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

public enum Code_Push_V1_TokenType: SwiftProtobuf.Enum {
  public typealias RawValue = Int
  case unknown // = 0

  /// FCM registration token for an Android device
  case fcmAndroid // = 1

  /// FCM registration token or an iOS device
  case fcmApns // = 2
  case UNRECOGNIZED(Int)

  public init() {
    self = .unknown
  }

  public init?(rawValue: Int) {
    switch rawValue {
    case 0: self = .unknown
    case 1: self = .fcmAndroid
    case 2: self = .fcmApns
    default: self = .UNRECOGNIZED(rawValue)
    }
  }

  public var rawValue: Int {
    switch self {
    case .unknown: return 0
    case .fcmAndroid: return 1
    case .fcmApns: return 2
    case .UNRECOGNIZED(let i): return i
    }
  }

}

#if swift(>=4.2)

extension Code_Push_V1_TokenType: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Push_V1_TokenType] = [
    .unknown,
    .fcmAndroid,
    .fcmApns,
  ]
}

#endif  // swift(>=4.2)

public struct Code_Push_V1_AddTokenRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The public key of the owner account that signed this request message.
  public var ownerAccountID: Code_Common_V1_SolanaAccountId {
    get {return _ownerAccountID ?? Code_Common_V1_SolanaAccountId()}
    set {_ownerAccountID = newValue}
  }
  /// Returns true if `ownerAccountID` has been explicitly set.
  public var hasOwnerAccountID: Bool {return self._ownerAccountID != nil}
  /// Clears the value of `ownerAccountID`. Subsequent reads from it will return its default value.
  public mutating func clearOwnerAccountID() {self._ownerAccountID = nil}

  /// The signature is of serialize(AddTokenRequest) without this field set
  /// using the private key of owner_account_id. This provides an authentication
  /// mechanism to the RPC.
  public var signature: Code_Common_V1_Signature {
    get {return _signature ?? Code_Common_V1_Signature()}
    set {_signature = newValue}
  }
  /// Returns true if `signature` has been explicitly set.
  public var hasSignature: Bool {return self._signature != nil}
  /// Clears the value of `signature`. Subsequent reads from it will return its default value.
  public mutating func clearSignature() {self._signature = nil}

  /// The data container where the push token will be stored.
  public var containerID: Code_Common_V1_DataContainerId {
    get {return _containerID ?? Code_Common_V1_DataContainerId()}
    set {_containerID = newValue}
  }
  /// Returns true if `containerID` has been explicitly set.
  public var hasContainerID: Bool {return self._containerID != nil}
  /// Clears the value of `containerID`. Subsequent reads from it will return its default value.
  public mutating func clearContainerID() {self._containerID = nil}

  /// The push token to store
  public var pushToken: String = String()

  /// The type of push token
  public var tokenType: Code_Push_V1_TokenType = .unknown

  /// The instance of the app install where the push token was generated. Ideally,
  /// the push token is unique to the install.
  public var appInstall: Code_Common_V1_AppInstallId {
    get {return _appInstall ?? Code_Common_V1_AppInstallId()}
    set {_appInstall = newValue}
  }
  /// Returns true if `appInstall` has been explicitly set.
  public var hasAppInstall: Bool {return self._appInstall != nil}
  /// Clears the value of `appInstall`. Subsequent reads from it will return its default value.
  public mutating func clearAppInstall() {self._appInstall = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}

  fileprivate var _ownerAccountID: Code_Common_V1_SolanaAccountId? = nil
  fileprivate var _signature: Code_Common_V1_Signature? = nil
  fileprivate var _containerID: Code_Common_V1_DataContainerId? = nil
  fileprivate var _appInstall: Code_Common_V1_AppInstallId? = nil
}

public struct Code_Push_V1_AddTokenResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var result: Code_Push_V1_AddTokenResponse.Result = .ok

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Result: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case ok // = 0

    /// The push token is invalid and wasn't stored.
    case invalidPushToken // = 1
    case UNRECOGNIZED(Int)

    public init() {
      self = .ok
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .ok
      case 1: self = .invalidPushToken
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .ok: return 0
      case .invalidPushToken: return 1
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Code_Push_V1_AddTokenResponse.Result: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Code_Push_V1_AddTokenResponse.Result] = [
    .ok,
    .invalidPushToken,
  ]
}

#endif  // swift(>=4.2)

#if swift(>=5.5) && canImport(_Concurrency)
extension Code_Push_V1_TokenType: @unchecked Sendable {}
extension Code_Push_V1_AddTokenRequest: @unchecked Sendable {}
extension Code_Push_V1_AddTokenResponse: @unchecked Sendable {}
extension Code_Push_V1_AddTokenResponse.Result: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "code.push.v1"

extension Code_Push_V1_TokenType: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "FCM_ANDROID"),
    2: .same(proto: "FCM_APNS"),
  ]
}

extension Code_Push_V1_AddTokenRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".AddTokenRequest"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "owner_account_id"),
    2: .same(proto: "signature"),
    3: .standard(proto: "container_id"),
    4: .standard(proto: "push_token"),
    5: .standard(proto: "token_type"),
    6: .standard(proto: "app_install"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularMessageField(value: &self._ownerAccountID) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._signature) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._containerID) }()
      case 4: try { try decoder.decodeSingularStringField(value: &self.pushToken) }()
      case 5: try { try decoder.decodeSingularEnumField(value: &self.tokenType) }()
      case 6: try { try decoder.decodeSingularMessageField(value: &self._appInstall) }()
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
    try { if let v = self._containerID {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    if !self.pushToken.isEmpty {
      try visitor.visitSingularStringField(value: self.pushToken, fieldNumber: 4)
    }
    if self.tokenType != .unknown {
      try visitor.visitSingularEnumField(value: self.tokenType, fieldNumber: 5)
    }
    try { if let v = self._appInstall {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 6)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Code_Push_V1_AddTokenRequest, rhs: Code_Push_V1_AddTokenRequest) -> Bool {
    if lhs._ownerAccountID != rhs._ownerAccountID {return false}
    if lhs._signature != rhs._signature {return false}
    if lhs._containerID != rhs._containerID {return false}
    if lhs.pushToken != rhs.pushToken {return false}
    if lhs.tokenType != rhs.tokenType {return false}
    if lhs._appInstall != rhs._appInstall {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Push_V1_AddTokenResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".AddTokenResponse"
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

  public static func ==(lhs: Code_Push_V1_AddTokenResponse, rhs: Code_Push_V1_AddTokenResponse) -> Bool {
    if lhs.result != rhs.result {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Code_Push_V1_AddTokenResponse.Result: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OK"),
    1: .same(proto: "INVALID_PUSH_TOKEN"),
  ]
}
