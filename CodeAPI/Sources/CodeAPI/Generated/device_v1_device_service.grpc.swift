//
// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the protocol buffer compiler.
// Source: device/v1/device_service.proto
//
import GRPC
import NIO
import NIOConcurrencyHelpers
import SwiftProtobuf


/// Usage: instantiate `Code_Device_V1_DeviceClient`, then call methods of this protocol to make API calls.
public protocol Code_Device_V1_DeviceClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol? { get }

  func registerLoggedInAccounts(
    _ request: Code_Device_V1_RegisterLoggedInAccountsRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_Device_V1_RegisterLoggedInAccountsRequest, Code_Device_V1_RegisterLoggedInAccountsResponse>

  func getLoggedInAccounts(
    _ request: Code_Device_V1_GetLoggedInAccountsRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_Device_V1_GetLoggedInAccountsRequest, Code_Device_V1_GetLoggedInAccountsResponse>
}

extension Code_Device_V1_DeviceClientProtocol {
  public var serviceName: String {
    return "code.device.v1.Device"
  }

  /// RegisterLoggedInAccounts registers a set of owner accounts logged for
  /// an app install. Currently, a single login is enforced per app install.
  /// After using GetLoggedInAccounts to detect stale logins, clients can use
  /// this RPC to update the set of accounts with valid login sessions.
  ///
  /// - Parameters:
  ///   - request: Request to send to RegisterLoggedInAccounts.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func registerLoggedInAccounts(
    _ request: Code_Device_V1_RegisterLoggedInAccountsRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_Device_V1_RegisterLoggedInAccountsRequest, Code_Device_V1_RegisterLoggedInAccountsResponse> {
    return self.makeUnaryCall(
      path: Code_Device_V1_DeviceClientMetadata.Methods.registerLoggedInAccounts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeRegisterLoggedInAccountsInterceptors() ?? []
    )
  }

  /// GetLoggedInAccounts gets the set of logged in accounts for an app install.
  /// Clients can use this RPC to detect stale logins for boot out of the app.
  ///
  /// - Parameters:
  ///   - request: Request to send to GetLoggedInAccounts.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getLoggedInAccounts(
    _ request: Code_Device_V1_GetLoggedInAccountsRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_Device_V1_GetLoggedInAccountsRequest, Code_Device_V1_GetLoggedInAccountsResponse> {
    return self.makeUnaryCall(
      path: Code_Device_V1_DeviceClientMetadata.Methods.getLoggedInAccounts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetLoggedInAccountsInterceptors() ?? []
    )
  }
}

@available(*, deprecated)
extension Code_Device_V1_DeviceClient: @unchecked Sendable {}

@available(*, deprecated, renamed: "Code_Device_V1_DeviceNIOClient")
public final class Code_Device_V1_DeviceClient: Code_Device_V1_DeviceClientProtocol {
  private let lock = Lock()
  private var _defaultCallOptions: CallOptions
  private var _interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol?
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions {
    get { self.lock.withLock { return self._defaultCallOptions } }
    set { self.lock.withLockVoid { self._defaultCallOptions = newValue } }
  }
  public var interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol? {
    get { self.lock.withLock { return self._interceptors } }
    set { self.lock.withLockVoid { self._interceptors = newValue } }
  }

  /// Creates a client for the code.device.v1.Device service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self._defaultCallOptions = defaultCallOptions
    self._interceptors = interceptors
  }
}

public struct Code_Device_V1_DeviceNIOClient: Code_Device_V1_DeviceClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol?

  /// Creates a client for the code.device.v1.Device service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Code_Device_V1_DeviceAsyncClientProtocol: GRPCClient {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol? { get }

  func makeRegisterLoggedInAccountsCall(
    _ request: Code_Device_V1_RegisterLoggedInAccountsRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_Device_V1_RegisterLoggedInAccountsRequest, Code_Device_V1_RegisterLoggedInAccountsResponse>

  func makeGetLoggedInAccountsCall(
    _ request: Code_Device_V1_GetLoggedInAccountsRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_Device_V1_GetLoggedInAccountsRequest, Code_Device_V1_GetLoggedInAccountsResponse>
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Device_V1_DeviceAsyncClientProtocol {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Code_Device_V1_DeviceClientMetadata.serviceDescriptor
  }

  public var interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol? {
    return nil
  }

  public func makeRegisterLoggedInAccountsCall(
    _ request: Code_Device_V1_RegisterLoggedInAccountsRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_Device_V1_RegisterLoggedInAccountsRequest, Code_Device_V1_RegisterLoggedInAccountsResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_Device_V1_DeviceClientMetadata.Methods.registerLoggedInAccounts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeRegisterLoggedInAccountsInterceptors() ?? []
    )
  }

  public func makeGetLoggedInAccountsCall(
    _ request: Code_Device_V1_GetLoggedInAccountsRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_Device_V1_GetLoggedInAccountsRequest, Code_Device_V1_GetLoggedInAccountsResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_Device_V1_DeviceClientMetadata.Methods.getLoggedInAccounts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetLoggedInAccountsInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Device_V1_DeviceAsyncClientProtocol {
  public func registerLoggedInAccounts(
    _ request: Code_Device_V1_RegisterLoggedInAccountsRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_Device_V1_RegisterLoggedInAccountsResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_Device_V1_DeviceClientMetadata.Methods.registerLoggedInAccounts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeRegisterLoggedInAccountsInterceptors() ?? []
    )
  }

  public func getLoggedInAccounts(
    _ request: Code_Device_V1_GetLoggedInAccountsRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_Device_V1_GetLoggedInAccountsResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_Device_V1_DeviceClientMetadata.Methods.getLoggedInAccounts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetLoggedInAccountsInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct Code_Device_V1_DeviceAsyncClient: Code_Device_V1_DeviceAsyncClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol?

  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Device_V1_DeviceClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

public protocol Code_Device_V1_DeviceClientInterceptorFactoryProtocol: Sendable {

  /// - Returns: Interceptors to use when invoking 'registerLoggedInAccounts'.
  func makeRegisterLoggedInAccountsInterceptors() -> [ClientInterceptor<Code_Device_V1_RegisterLoggedInAccountsRequest, Code_Device_V1_RegisterLoggedInAccountsResponse>]

  /// - Returns: Interceptors to use when invoking 'getLoggedInAccounts'.
  func makeGetLoggedInAccountsInterceptors() -> [ClientInterceptor<Code_Device_V1_GetLoggedInAccountsRequest, Code_Device_V1_GetLoggedInAccountsResponse>]
}

public enum Code_Device_V1_DeviceClientMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "Device",
    fullName: "code.device.v1.Device",
    methods: [
      Code_Device_V1_DeviceClientMetadata.Methods.registerLoggedInAccounts,
      Code_Device_V1_DeviceClientMetadata.Methods.getLoggedInAccounts,
    ]
  )

  public enum Methods {
    public static let registerLoggedInAccounts = GRPCMethodDescriptor(
      name: "RegisterLoggedInAccounts",
      path: "/code.device.v1.Device/RegisterLoggedInAccounts",
      type: GRPCCallType.unary
    )

    public static let getLoggedInAccounts = GRPCMethodDescriptor(
      name: "GetLoggedInAccounts",
      path: "/code.device.v1.Device/GetLoggedInAccounts",
      type: GRPCCallType.unary
    )
  }
}

/// To build a server, implement a class that conforms to this protocol.
public protocol Code_Device_V1_DeviceProvider: CallHandlerProvider {
  var interceptors: Code_Device_V1_DeviceServerInterceptorFactoryProtocol? { get }

  /// RegisterLoggedInAccounts registers a set of owner accounts logged for
  /// an app install. Currently, a single login is enforced per app install.
  /// After using GetLoggedInAccounts to detect stale logins, clients can use
  /// this RPC to update the set of accounts with valid login sessions.
  func registerLoggedInAccounts(request: Code_Device_V1_RegisterLoggedInAccountsRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_Device_V1_RegisterLoggedInAccountsResponse>

  /// GetLoggedInAccounts gets the set of logged in accounts for an app install.
  /// Clients can use this RPC to detect stale logins for boot out of the app.
  func getLoggedInAccounts(request: Code_Device_V1_GetLoggedInAccountsRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_Device_V1_GetLoggedInAccountsResponse>
}

extension Code_Device_V1_DeviceProvider {
  public var serviceName: Substring {
    return Code_Device_V1_DeviceServerMetadata.serviceDescriptor.fullName[...]
  }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "RegisterLoggedInAccounts":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Device_V1_RegisterLoggedInAccountsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Device_V1_RegisterLoggedInAccountsResponse>(),
        interceptors: self.interceptors?.makeRegisterLoggedInAccountsInterceptors() ?? [],
        userFunction: self.registerLoggedInAccounts(request:context:)
      )

    case "GetLoggedInAccounts":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Device_V1_GetLoggedInAccountsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Device_V1_GetLoggedInAccountsResponse>(),
        interceptors: self.interceptors?.makeGetLoggedInAccountsInterceptors() ?? [],
        userFunction: self.getLoggedInAccounts(request:context:)
      )

    default:
      return nil
    }
  }
}

/// To implement a server, implement an object which conforms to this protocol.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Code_Device_V1_DeviceAsyncProvider: CallHandlerProvider, Sendable {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Code_Device_V1_DeviceServerInterceptorFactoryProtocol? { get }

  /// RegisterLoggedInAccounts registers a set of owner accounts logged for
  /// an app install. Currently, a single login is enforced per app install.
  /// After using GetLoggedInAccounts to detect stale logins, clients can use
  /// this RPC to update the set of accounts with valid login sessions.
  func registerLoggedInAccounts(
    request: Code_Device_V1_RegisterLoggedInAccountsRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_Device_V1_RegisterLoggedInAccountsResponse

  /// GetLoggedInAccounts gets the set of logged in accounts for an app install.
  /// Clients can use this RPC to detect stale logins for boot out of the app.
  func getLoggedInAccounts(
    request: Code_Device_V1_GetLoggedInAccountsRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_Device_V1_GetLoggedInAccountsResponse
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Device_V1_DeviceAsyncProvider {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Code_Device_V1_DeviceServerMetadata.serviceDescriptor
  }

  public var serviceName: Substring {
    return Code_Device_V1_DeviceServerMetadata.serviceDescriptor.fullName[...]
  }

  public var interceptors: Code_Device_V1_DeviceServerInterceptorFactoryProtocol? {
    return nil
  }

  public func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "RegisterLoggedInAccounts":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Device_V1_RegisterLoggedInAccountsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Device_V1_RegisterLoggedInAccountsResponse>(),
        interceptors: self.interceptors?.makeRegisterLoggedInAccountsInterceptors() ?? [],
        wrapping: { try await self.registerLoggedInAccounts(request: $0, context: $1) }
      )

    case "GetLoggedInAccounts":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Device_V1_GetLoggedInAccountsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Device_V1_GetLoggedInAccountsResponse>(),
        interceptors: self.interceptors?.makeGetLoggedInAccountsInterceptors() ?? [],
        wrapping: { try await self.getLoggedInAccounts(request: $0, context: $1) }
      )

    default:
      return nil
    }
  }
}

public protocol Code_Device_V1_DeviceServerInterceptorFactoryProtocol: Sendable {

  /// - Returns: Interceptors to use when handling 'registerLoggedInAccounts'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeRegisterLoggedInAccountsInterceptors() -> [ServerInterceptor<Code_Device_V1_RegisterLoggedInAccountsRequest, Code_Device_V1_RegisterLoggedInAccountsResponse>]

  /// - Returns: Interceptors to use when handling 'getLoggedInAccounts'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeGetLoggedInAccountsInterceptors() -> [ServerInterceptor<Code_Device_V1_GetLoggedInAccountsRequest, Code_Device_V1_GetLoggedInAccountsResponse>]
}

public enum Code_Device_V1_DeviceServerMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "Device",
    fullName: "code.device.v1.Device",
    methods: [
      Code_Device_V1_DeviceServerMetadata.Methods.registerLoggedInAccounts,
      Code_Device_V1_DeviceServerMetadata.Methods.getLoggedInAccounts,
    ]
  )

  public enum Methods {
    public static let registerLoggedInAccounts = GRPCMethodDescriptor(
      name: "RegisterLoggedInAccounts",
      path: "/code.device.v1.Device/RegisterLoggedInAccounts",
      type: GRPCCallType.unary
    )

    public static let getLoggedInAccounts = GRPCMethodDescriptor(
      name: "GetLoggedInAccounts",
      path: "/code.device.v1.Device/GetLoggedInAccounts",
      type: GRPCCallType.unary
    )
  }
}
