//
// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the protocol buffer compiler.
// Source: phone/v1/phone_verification_service.proto
//
import GRPC
import NIO
import NIOConcurrencyHelpers
import SwiftProtobuf


/// Usage: instantiate `Code_Phone_V1_PhoneVerificationClient`, then call methods of this protocol to make API calls.
public protocol Code_Phone_V1_PhoneVerificationClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol? { get }

  func sendVerificationCode(
    _ request: Code_Phone_V1_SendVerificationCodeRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_Phone_V1_SendVerificationCodeRequest, Code_Phone_V1_SendVerificationCodeResponse>

  func checkVerificationCode(
    _ request: Code_Phone_V1_CheckVerificationCodeRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_Phone_V1_CheckVerificationCodeRequest, Code_Phone_V1_CheckVerificationCodeResponse>

  func getAssociatedPhoneNumber(
    _ request: Code_Phone_V1_GetAssociatedPhoneNumberRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_Phone_V1_GetAssociatedPhoneNumberRequest, Code_Phone_V1_GetAssociatedPhoneNumberResponse>
}

extension Code_Phone_V1_PhoneVerificationClientProtocol {
  public var serviceName: String {
    return "code.phone.v1.PhoneVerification"
  }

  /// SendVerificationCode sends a verification code to the provided phone number
  /// over SMS. If an active verification is already taking place, the existing code
  /// will be resent.
  ///
  /// - Parameters:
  ///   - request: Request to send to SendVerificationCode.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func sendVerificationCode(
    _ request: Code_Phone_V1_SendVerificationCodeRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_Phone_V1_SendVerificationCodeRequest, Code_Phone_V1_SendVerificationCodeResponse> {
    return self.makeUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.sendVerificationCode.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeSendVerificationCodeInterceptors() ?? []
    )
  }

  /// CheckVerificationCode validates a verification code. On success, a one-time use
  /// token to link an owner account is provided. 
  ///
  /// - Parameters:
  ///   - request: Request to send to CheckVerificationCode.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func checkVerificationCode(
    _ request: Code_Phone_V1_CheckVerificationCodeRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_Phone_V1_CheckVerificationCodeRequest, Code_Phone_V1_CheckVerificationCodeResponse> {
    return self.makeUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.checkVerificationCode.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCheckVerificationCodeInterceptors() ?? []
    )
  }

  /// GetAssociatedPhoneNumber gets the latest verified phone number linked to an owner account.
  ///
  /// - Parameters:
  ///   - request: Request to send to GetAssociatedPhoneNumber.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getAssociatedPhoneNumber(
    _ request: Code_Phone_V1_GetAssociatedPhoneNumberRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_Phone_V1_GetAssociatedPhoneNumberRequest, Code_Phone_V1_GetAssociatedPhoneNumberResponse> {
    return self.makeUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.getAssociatedPhoneNumber.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAssociatedPhoneNumberInterceptors() ?? []
    )
  }
}

@available(*, deprecated)
extension Code_Phone_V1_PhoneVerificationClient: @unchecked Sendable {}

@available(*, deprecated, renamed: "Code_Phone_V1_PhoneVerificationNIOClient")
public final class Code_Phone_V1_PhoneVerificationClient: Code_Phone_V1_PhoneVerificationClientProtocol {
  private let lock = Lock()
  private var _defaultCallOptions: CallOptions
  private var _interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol?
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions {
    get { self.lock.withLock { return self._defaultCallOptions } }
    set { self.lock.withLockVoid { self._defaultCallOptions = newValue } }
  }
  public var interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol? {
    get { self.lock.withLock { return self._interceptors } }
    set { self.lock.withLockVoid { self._interceptors = newValue } }
  }

  /// Creates a client for the code.phone.v1.PhoneVerification service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self._defaultCallOptions = defaultCallOptions
    self._interceptors = interceptors
  }
}

public struct Code_Phone_V1_PhoneVerificationNIOClient: Code_Phone_V1_PhoneVerificationClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol?

  /// Creates a client for the code.phone.v1.PhoneVerification service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Code_Phone_V1_PhoneVerificationAsyncClientProtocol: GRPCClient {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol? { get }

  func makeSendVerificationCodeCall(
    _ request: Code_Phone_V1_SendVerificationCodeRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_Phone_V1_SendVerificationCodeRequest, Code_Phone_V1_SendVerificationCodeResponse>

  func makeCheckVerificationCodeCall(
    _ request: Code_Phone_V1_CheckVerificationCodeRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_Phone_V1_CheckVerificationCodeRequest, Code_Phone_V1_CheckVerificationCodeResponse>

  func makeGetAssociatedPhoneNumberCall(
    _ request: Code_Phone_V1_GetAssociatedPhoneNumberRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_Phone_V1_GetAssociatedPhoneNumberRequest, Code_Phone_V1_GetAssociatedPhoneNumberResponse>
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Phone_V1_PhoneVerificationAsyncClientProtocol {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Code_Phone_V1_PhoneVerificationClientMetadata.serviceDescriptor
  }

  public var interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol? {
    return nil
  }

  public func makeSendVerificationCodeCall(
    _ request: Code_Phone_V1_SendVerificationCodeRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_Phone_V1_SendVerificationCodeRequest, Code_Phone_V1_SendVerificationCodeResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.sendVerificationCode.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeSendVerificationCodeInterceptors() ?? []
    )
  }

  public func makeCheckVerificationCodeCall(
    _ request: Code_Phone_V1_CheckVerificationCodeRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_Phone_V1_CheckVerificationCodeRequest, Code_Phone_V1_CheckVerificationCodeResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.checkVerificationCode.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCheckVerificationCodeInterceptors() ?? []
    )
  }

  public func makeGetAssociatedPhoneNumberCall(
    _ request: Code_Phone_V1_GetAssociatedPhoneNumberRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_Phone_V1_GetAssociatedPhoneNumberRequest, Code_Phone_V1_GetAssociatedPhoneNumberResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.getAssociatedPhoneNumber.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAssociatedPhoneNumberInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Phone_V1_PhoneVerificationAsyncClientProtocol {
  public func sendVerificationCode(
    _ request: Code_Phone_V1_SendVerificationCodeRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_Phone_V1_SendVerificationCodeResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.sendVerificationCode.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeSendVerificationCodeInterceptors() ?? []
    )
  }

  public func checkVerificationCode(
    _ request: Code_Phone_V1_CheckVerificationCodeRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_Phone_V1_CheckVerificationCodeResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.checkVerificationCode.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeCheckVerificationCodeInterceptors() ?? []
    )
  }

  public func getAssociatedPhoneNumber(
    _ request: Code_Phone_V1_GetAssociatedPhoneNumberRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_Phone_V1_GetAssociatedPhoneNumberResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_Phone_V1_PhoneVerificationClientMetadata.Methods.getAssociatedPhoneNumber.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetAssociatedPhoneNumberInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct Code_Phone_V1_PhoneVerificationAsyncClient: Code_Phone_V1_PhoneVerificationAsyncClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol?

  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

public protocol Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol: Sendable {

  /// - Returns: Interceptors to use when invoking 'sendVerificationCode'.
  func makeSendVerificationCodeInterceptors() -> [ClientInterceptor<Code_Phone_V1_SendVerificationCodeRequest, Code_Phone_V1_SendVerificationCodeResponse>]

  /// - Returns: Interceptors to use when invoking 'checkVerificationCode'.
  func makeCheckVerificationCodeInterceptors() -> [ClientInterceptor<Code_Phone_V1_CheckVerificationCodeRequest, Code_Phone_V1_CheckVerificationCodeResponse>]

  /// - Returns: Interceptors to use when invoking 'getAssociatedPhoneNumber'.
  func makeGetAssociatedPhoneNumberInterceptors() -> [ClientInterceptor<Code_Phone_V1_GetAssociatedPhoneNumberRequest, Code_Phone_V1_GetAssociatedPhoneNumberResponse>]
}

public enum Code_Phone_V1_PhoneVerificationClientMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "PhoneVerification",
    fullName: "code.phone.v1.PhoneVerification",
    methods: [
      Code_Phone_V1_PhoneVerificationClientMetadata.Methods.sendVerificationCode,
      Code_Phone_V1_PhoneVerificationClientMetadata.Methods.checkVerificationCode,
      Code_Phone_V1_PhoneVerificationClientMetadata.Methods.getAssociatedPhoneNumber,
    ]
  )

  public enum Methods {
    public static let sendVerificationCode = GRPCMethodDescriptor(
      name: "SendVerificationCode",
      path: "/code.phone.v1.PhoneVerification/SendVerificationCode",
      type: GRPCCallType.unary
    )

    public static let checkVerificationCode = GRPCMethodDescriptor(
      name: "CheckVerificationCode",
      path: "/code.phone.v1.PhoneVerification/CheckVerificationCode",
      type: GRPCCallType.unary
    )

    public static let getAssociatedPhoneNumber = GRPCMethodDescriptor(
      name: "GetAssociatedPhoneNumber",
      path: "/code.phone.v1.PhoneVerification/GetAssociatedPhoneNumber",
      type: GRPCCallType.unary
    )
  }
}

/// To build a server, implement a class that conforms to this protocol.
public protocol Code_Phone_V1_PhoneVerificationProvider: CallHandlerProvider {
  var interceptors: Code_Phone_V1_PhoneVerificationServerInterceptorFactoryProtocol? { get }

  /// SendVerificationCode sends a verification code to the provided phone number
  /// over SMS. If an active verification is already taking place, the existing code
  /// will be resent.
  func sendVerificationCode(request: Code_Phone_V1_SendVerificationCodeRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_Phone_V1_SendVerificationCodeResponse>

  /// CheckVerificationCode validates a verification code. On success, a one-time use
  /// token to link an owner account is provided. 
  func checkVerificationCode(request: Code_Phone_V1_CheckVerificationCodeRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_Phone_V1_CheckVerificationCodeResponse>

  /// GetAssociatedPhoneNumber gets the latest verified phone number linked to an owner account.
  func getAssociatedPhoneNumber(request: Code_Phone_V1_GetAssociatedPhoneNumberRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_Phone_V1_GetAssociatedPhoneNumberResponse>
}

extension Code_Phone_V1_PhoneVerificationProvider {
  public var serviceName: Substring {
    return Code_Phone_V1_PhoneVerificationServerMetadata.serviceDescriptor.fullName[...]
  }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "SendVerificationCode":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Phone_V1_SendVerificationCodeRequest>(),
        responseSerializer: ProtobufSerializer<Code_Phone_V1_SendVerificationCodeResponse>(),
        interceptors: self.interceptors?.makeSendVerificationCodeInterceptors() ?? [],
        userFunction: self.sendVerificationCode(request:context:)
      )

    case "CheckVerificationCode":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Phone_V1_CheckVerificationCodeRequest>(),
        responseSerializer: ProtobufSerializer<Code_Phone_V1_CheckVerificationCodeResponse>(),
        interceptors: self.interceptors?.makeCheckVerificationCodeInterceptors() ?? [],
        userFunction: self.checkVerificationCode(request:context:)
      )

    case "GetAssociatedPhoneNumber":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Phone_V1_GetAssociatedPhoneNumberRequest>(),
        responseSerializer: ProtobufSerializer<Code_Phone_V1_GetAssociatedPhoneNumberResponse>(),
        interceptors: self.interceptors?.makeGetAssociatedPhoneNumberInterceptors() ?? [],
        userFunction: self.getAssociatedPhoneNumber(request:context:)
      )

    default:
      return nil
    }
  }
}

/// To implement a server, implement an object which conforms to this protocol.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Code_Phone_V1_PhoneVerificationAsyncProvider: CallHandlerProvider, Sendable {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Code_Phone_V1_PhoneVerificationServerInterceptorFactoryProtocol? { get }

  /// SendVerificationCode sends a verification code to the provided phone number
  /// over SMS. If an active verification is already taking place, the existing code
  /// will be resent.
  func sendVerificationCode(
    request: Code_Phone_V1_SendVerificationCodeRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_Phone_V1_SendVerificationCodeResponse

  /// CheckVerificationCode validates a verification code. On success, a one-time use
  /// token to link an owner account is provided. 
  func checkVerificationCode(
    request: Code_Phone_V1_CheckVerificationCodeRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_Phone_V1_CheckVerificationCodeResponse

  /// GetAssociatedPhoneNumber gets the latest verified phone number linked to an owner account.
  func getAssociatedPhoneNumber(
    request: Code_Phone_V1_GetAssociatedPhoneNumberRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_Phone_V1_GetAssociatedPhoneNumberResponse
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Phone_V1_PhoneVerificationAsyncProvider {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Code_Phone_V1_PhoneVerificationServerMetadata.serviceDescriptor
  }

  public var serviceName: Substring {
    return Code_Phone_V1_PhoneVerificationServerMetadata.serviceDescriptor.fullName[...]
  }

  public var interceptors: Code_Phone_V1_PhoneVerificationServerInterceptorFactoryProtocol? {
    return nil
  }

  public func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "SendVerificationCode":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Phone_V1_SendVerificationCodeRequest>(),
        responseSerializer: ProtobufSerializer<Code_Phone_V1_SendVerificationCodeResponse>(),
        interceptors: self.interceptors?.makeSendVerificationCodeInterceptors() ?? [],
        wrapping: { try await self.sendVerificationCode(request: $0, context: $1) }
      )

    case "CheckVerificationCode":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Phone_V1_CheckVerificationCodeRequest>(),
        responseSerializer: ProtobufSerializer<Code_Phone_V1_CheckVerificationCodeResponse>(),
        interceptors: self.interceptors?.makeCheckVerificationCodeInterceptors() ?? [],
        wrapping: { try await self.checkVerificationCode(request: $0, context: $1) }
      )

    case "GetAssociatedPhoneNumber":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Phone_V1_GetAssociatedPhoneNumberRequest>(),
        responseSerializer: ProtobufSerializer<Code_Phone_V1_GetAssociatedPhoneNumberResponse>(),
        interceptors: self.interceptors?.makeGetAssociatedPhoneNumberInterceptors() ?? [],
        wrapping: { try await self.getAssociatedPhoneNumber(request: $0, context: $1) }
      )

    default:
      return nil
    }
  }
}

public protocol Code_Phone_V1_PhoneVerificationServerInterceptorFactoryProtocol: Sendable {

  /// - Returns: Interceptors to use when handling 'sendVerificationCode'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeSendVerificationCodeInterceptors() -> [ServerInterceptor<Code_Phone_V1_SendVerificationCodeRequest, Code_Phone_V1_SendVerificationCodeResponse>]

  /// - Returns: Interceptors to use when handling 'checkVerificationCode'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeCheckVerificationCodeInterceptors() -> [ServerInterceptor<Code_Phone_V1_CheckVerificationCodeRequest, Code_Phone_V1_CheckVerificationCodeResponse>]

  /// - Returns: Interceptors to use when handling 'getAssociatedPhoneNumber'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeGetAssociatedPhoneNumberInterceptors() -> [ServerInterceptor<Code_Phone_V1_GetAssociatedPhoneNumberRequest, Code_Phone_V1_GetAssociatedPhoneNumberResponse>]
}

public enum Code_Phone_V1_PhoneVerificationServerMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "PhoneVerification",
    fullName: "code.phone.v1.PhoneVerification",
    methods: [
      Code_Phone_V1_PhoneVerificationServerMetadata.Methods.sendVerificationCode,
      Code_Phone_V1_PhoneVerificationServerMetadata.Methods.checkVerificationCode,
      Code_Phone_V1_PhoneVerificationServerMetadata.Methods.getAssociatedPhoneNumber,
    ]
  )

  public enum Methods {
    public static let sendVerificationCode = GRPCMethodDescriptor(
      name: "SendVerificationCode",
      path: "/code.phone.v1.PhoneVerification/SendVerificationCode",
      type: GRPCCallType.unary
    )

    public static let checkVerificationCode = GRPCMethodDescriptor(
      name: "CheckVerificationCode",
      path: "/code.phone.v1.PhoneVerification/CheckVerificationCode",
      type: GRPCCallType.unary
    )

    public static let getAssociatedPhoneNumber = GRPCMethodDescriptor(
      name: "GetAssociatedPhoneNumber",
      path: "/code.phone.v1.PhoneVerification/GetAssociatedPhoneNumber",
      type: GRPCCallType.unary
    )
  }
}
