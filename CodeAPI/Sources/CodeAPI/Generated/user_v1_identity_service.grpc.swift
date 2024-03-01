//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: user/v1/identity_service.proto
//

//
// Copyright 2018, gRPC Authors All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
import GRPC
import NIO
import NIOConcurrencyHelpers
import SwiftProtobuf


/// Usage: instantiate `Code_User_V1_IdentityClient`, then call methods of this protocol to make API calls.
public protocol Code_User_V1_IdentityClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol? { get }

  func linkAccount(
    _ request: Code_User_V1_LinkAccountRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_User_V1_LinkAccountRequest, Code_User_V1_LinkAccountResponse>

  func unlinkAccount(
    _ request: Code_User_V1_UnlinkAccountRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_User_V1_UnlinkAccountRequest, Code_User_V1_UnlinkAccountResponse>

  func getUser(
    _ request: Code_User_V1_GetUserRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_User_V1_GetUserRequest, Code_User_V1_GetUserResponse>

  func updatePreferences(
    _ request: Code_User_V1_UpdatePreferencesRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_User_V1_UpdatePreferencesRequest, Code_User_V1_UpdatePreferencesResponse>

  func loginToThirdPartyApp(
    _ request: Code_User_V1_LoginToThirdPartyAppRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_User_V1_LoginToThirdPartyAppRequest, Code_User_V1_LoginToThirdPartyAppResponse>

  func getLoginForThirdPartyApp(
    _ request: Code_User_V1_GetLoginForThirdPartyAppRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_User_V1_GetLoginForThirdPartyAppRequest, Code_User_V1_GetLoginForThirdPartyAppResponse>
}

extension Code_User_V1_IdentityClientProtocol {
  public var serviceName: String {
    return "code.user.v1.Identity"
  }

  /// LinkAccount links an owner account to the user identified and authenticated
  /// by a one-time use token.
  ///
  /// Notably, this RPC has the following side effects:
  ///   * A new user is automatically created if one doesn't exist.
  ///   * Server will create a new data container for at least every unique
  ///     owner account linked to the user.
  ///
  /// - Parameters:
  ///   - request: Request to send to LinkAccount.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func linkAccount(
    _ request: Code_User_V1_LinkAccountRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_User_V1_LinkAccountRequest, Code_User_V1_LinkAccountResponse> {
    return self.makeUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.linkAccount.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeLinkAccountInterceptors() ?? []
    )
  }

  /// UnlinkAccount removes links from an owner account. It will NOT remove
  /// existing associations between users, owner accounts and identifying
  /// features.
  ///
  /// The following associations will remain intact to ensure owner accounts
  /// can continue to be used with a consistent login experience:
  ///   * the user continues to be associated to existing owner accounts and
  ///     identifying features
  ///
  /// Client can continue mainting their current login session. Their current
  /// user and data container will remain the same.
  ///
  /// The call is guaranteed to be idempotent. It will not fail if the link is
  /// already removed by either a previous call to this RPC or by a more recent
  /// call to LinkAccount. A failure will only occur if the link between a user
  /// and the owner accout or identifying feature never existed.
  ///
  /// - Parameters:
  ///   - request: Request to send to UnlinkAccount.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func unlinkAccount(
    _ request: Code_User_V1_UnlinkAccountRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_User_V1_UnlinkAccountRequest, Code_User_V1_UnlinkAccountResponse> {
    return self.makeUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.unlinkAccount.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUnlinkAccountInterceptors() ?? []
    )
  }

  /// GetUser gets user information given a user identifier and an owner account.
  ///
  /// - Parameters:
  ///   - request: Request to send to GetUser.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getUser(
    _ request: Code_User_V1_GetUserRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_User_V1_GetUserRequest, Code_User_V1_GetUserResponse> {
    return self.makeUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.getUser.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetUserInterceptors() ?? []
    )
  }

  /// UpdatePreferences updates user preferences.
  ///
  /// - Parameters:
  ///   - request: Request to send to UpdatePreferences.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func updatePreferences(
    _ request: Code_User_V1_UpdatePreferencesRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_User_V1_UpdatePreferencesRequest, Code_User_V1_UpdatePreferencesResponse> {
    return self.makeUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.updatePreferences.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUpdatePreferencesInterceptors() ?? []
    )
  }

  /// LoginToThirdPartyApp logs a user into a third party app for a given intent
  /// ID. If the original request requires payment, then SubmitIntent must be called.
  ///
  /// - Parameters:
  ///   - request: Request to send to LoginToThirdPartyApp.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func loginToThirdPartyApp(
    _ request: Code_User_V1_LoginToThirdPartyAppRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_User_V1_LoginToThirdPartyAppRequest, Code_User_V1_LoginToThirdPartyAppResponse> {
    return self.makeUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.loginToThirdPartyApp.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeLoginToThirdPartyAppInterceptors() ?? []
    )
  }

  /// GetLoginForThirdPartyApp gets a login for a third party app from an existing
  /// request. This endpoint supports all paths where login is possible (login on payment,
  /// raw login, etc.).
  ///
  /// - Parameters:
  ///   - request: Request to send to GetLoginForThirdPartyApp.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getLoginForThirdPartyApp(
    _ request: Code_User_V1_GetLoginForThirdPartyAppRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_User_V1_GetLoginForThirdPartyAppRequest, Code_User_V1_GetLoginForThirdPartyAppResponse> {
    return self.makeUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.getLoginForThirdPartyApp.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetLoginForThirdPartyAppInterceptors() ?? []
    )
  }
}

#if compiler(>=5.6)
@available(*, deprecated)
extension Code_User_V1_IdentityClient: @unchecked Sendable {}
#endif // compiler(>=5.6)

@available(*, deprecated, renamed: "Code_User_V1_IdentityNIOClient")
public final class Code_User_V1_IdentityClient: Code_User_V1_IdentityClientProtocol {
  private let lock = Lock()
  private var _defaultCallOptions: CallOptions
  private var _interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol?
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions {
    get { self.lock.withLock { return self._defaultCallOptions } }
    set { self.lock.withLockVoid { self._defaultCallOptions = newValue } }
  }
  public var interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol? {
    get { self.lock.withLock { return self._interceptors } }
    set { self.lock.withLockVoid { self._interceptors = newValue } }
  }

  /// Creates a client for the code.user.v1.Identity service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self._defaultCallOptions = defaultCallOptions
    self._interceptors = interceptors
  }
}

public struct Code_User_V1_IdentityNIOClient: Code_User_V1_IdentityClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol?

  /// Creates a client for the code.user.v1.Identity service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

#if compiler(>=5.6)
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Code_User_V1_IdentityAsyncClientProtocol: GRPCClient {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol? { get }

  func makeLinkAccountCall(
    _ request: Code_User_V1_LinkAccountRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_User_V1_LinkAccountRequest, Code_User_V1_LinkAccountResponse>

  func makeUnlinkAccountCall(
    _ request: Code_User_V1_UnlinkAccountRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_User_V1_UnlinkAccountRequest, Code_User_V1_UnlinkAccountResponse>

  func makeGetUserCall(
    _ request: Code_User_V1_GetUserRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_User_V1_GetUserRequest, Code_User_V1_GetUserResponse>

  func makeUpdatePreferencesCall(
    _ request: Code_User_V1_UpdatePreferencesRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_User_V1_UpdatePreferencesRequest, Code_User_V1_UpdatePreferencesResponse>

  func makeLoginToThirdPartyAppCall(
    _ request: Code_User_V1_LoginToThirdPartyAppRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_User_V1_LoginToThirdPartyAppRequest, Code_User_V1_LoginToThirdPartyAppResponse>

  func makeGetLoginForThirdPartyAppCall(
    _ request: Code_User_V1_GetLoginForThirdPartyAppRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_User_V1_GetLoginForThirdPartyAppRequest, Code_User_V1_GetLoginForThirdPartyAppResponse>
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_User_V1_IdentityAsyncClientProtocol {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Code_User_V1_IdentityClientMetadata.serviceDescriptor
  }

  public var interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol? {
    return nil
  }

  public func makeLinkAccountCall(
    _ request: Code_User_V1_LinkAccountRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_User_V1_LinkAccountRequest, Code_User_V1_LinkAccountResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.linkAccount.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeLinkAccountInterceptors() ?? []
    )
  }

  public func makeUnlinkAccountCall(
    _ request: Code_User_V1_UnlinkAccountRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_User_V1_UnlinkAccountRequest, Code_User_V1_UnlinkAccountResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.unlinkAccount.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUnlinkAccountInterceptors() ?? []
    )
  }

  public func makeGetUserCall(
    _ request: Code_User_V1_GetUserRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_User_V1_GetUserRequest, Code_User_V1_GetUserResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.getUser.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetUserInterceptors() ?? []
    )
  }

  public func makeUpdatePreferencesCall(
    _ request: Code_User_V1_UpdatePreferencesRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_User_V1_UpdatePreferencesRequest, Code_User_V1_UpdatePreferencesResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.updatePreferences.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUpdatePreferencesInterceptors() ?? []
    )
  }

  public func makeLoginToThirdPartyAppCall(
    _ request: Code_User_V1_LoginToThirdPartyAppRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_User_V1_LoginToThirdPartyAppRequest, Code_User_V1_LoginToThirdPartyAppResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.loginToThirdPartyApp.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeLoginToThirdPartyAppInterceptors() ?? []
    )
  }

  public func makeGetLoginForThirdPartyAppCall(
    _ request: Code_User_V1_GetLoginForThirdPartyAppRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_User_V1_GetLoginForThirdPartyAppRequest, Code_User_V1_GetLoginForThirdPartyAppResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.getLoginForThirdPartyApp.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetLoginForThirdPartyAppInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_User_V1_IdentityAsyncClientProtocol {
  public func linkAccount(
    _ request: Code_User_V1_LinkAccountRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_User_V1_LinkAccountResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.linkAccount.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeLinkAccountInterceptors() ?? []
    )
  }

  public func unlinkAccount(
    _ request: Code_User_V1_UnlinkAccountRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_User_V1_UnlinkAccountResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.unlinkAccount.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUnlinkAccountInterceptors() ?? []
    )
  }

  public func getUser(
    _ request: Code_User_V1_GetUserRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_User_V1_GetUserResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.getUser.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetUserInterceptors() ?? []
    )
  }

  public func updatePreferences(
    _ request: Code_User_V1_UpdatePreferencesRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_User_V1_UpdatePreferencesResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.updatePreferences.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeUpdatePreferencesInterceptors() ?? []
    )
  }

  public func loginToThirdPartyApp(
    _ request: Code_User_V1_LoginToThirdPartyAppRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_User_V1_LoginToThirdPartyAppResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.loginToThirdPartyApp.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeLoginToThirdPartyAppInterceptors() ?? []
    )
  }

  public func getLoginForThirdPartyApp(
    _ request: Code_User_V1_GetLoginForThirdPartyAppRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_User_V1_GetLoginForThirdPartyAppResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_User_V1_IdentityClientMetadata.Methods.getLoginForThirdPartyApp.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetLoginForThirdPartyAppInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct Code_User_V1_IdentityAsyncClient: Code_User_V1_IdentityAsyncClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol?

  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_User_V1_IdentityClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

#endif // compiler(>=5.6)

public protocol Code_User_V1_IdentityClientInterceptorFactoryProtocol: GRPCSendable {

  /// - Returns: Interceptors to use when invoking 'linkAccount'.
  func makeLinkAccountInterceptors() -> [ClientInterceptor<Code_User_V1_LinkAccountRequest, Code_User_V1_LinkAccountResponse>]

  /// - Returns: Interceptors to use when invoking 'unlinkAccount'.
  func makeUnlinkAccountInterceptors() -> [ClientInterceptor<Code_User_V1_UnlinkAccountRequest, Code_User_V1_UnlinkAccountResponse>]

  /// - Returns: Interceptors to use when invoking 'getUser'.
  func makeGetUserInterceptors() -> [ClientInterceptor<Code_User_V1_GetUserRequest, Code_User_V1_GetUserResponse>]

  /// - Returns: Interceptors to use when invoking 'updatePreferences'.
  func makeUpdatePreferencesInterceptors() -> [ClientInterceptor<Code_User_V1_UpdatePreferencesRequest, Code_User_V1_UpdatePreferencesResponse>]

  /// - Returns: Interceptors to use when invoking 'loginToThirdPartyApp'.
  func makeLoginToThirdPartyAppInterceptors() -> [ClientInterceptor<Code_User_V1_LoginToThirdPartyAppRequest, Code_User_V1_LoginToThirdPartyAppResponse>]

  /// - Returns: Interceptors to use when invoking 'getLoginForThirdPartyApp'.
  func makeGetLoginForThirdPartyAppInterceptors() -> [ClientInterceptor<Code_User_V1_GetLoginForThirdPartyAppRequest, Code_User_V1_GetLoginForThirdPartyAppResponse>]
}

public enum Code_User_V1_IdentityClientMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "Identity",
    fullName: "code.user.v1.Identity",
    methods: [
      Code_User_V1_IdentityClientMetadata.Methods.linkAccount,
      Code_User_V1_IdentityClientMetadata.Methods.unlinkAccount,
      Code_User_V1_IdentityClientMetadata.Methods.getUser,
      Code_User_V1_IdentityClientMetadata.Methods.updatePreferences,
      Code_User_V1_IdentityClientMetadata.Methods.loginToThirdPartyApp,
      Code_User_V1_IdentityClientMetadata.Methods.getLoginForThirdPartyApp,
    ]
  )

  public enum Methods {
    public static let linkAccount = GRPCMethodDescriptor(
      name: "LinkAccount",
      path: "/code.user.v1.Identity/LinkAccount",
      type: GRPCCallType.unary
    )

    public static let unlinkAccount = GRPCMethodDescriptor(
      name: "UnlinkAccount",
      path: "/code.user.v1.Identity/UnlinkAccount",
      type: GRPCCallType.unary
    )

    public static let getUser = GRPCMethodDescriptor(
      name: "GetUser",
      path: "/code.user.v1.Identity/GetUser",
      type: GRPCCallType.unary
    )

    public static let updatePreferences = GRPCMethodDescriptor(
      name: "UpdatePreferences",
      path: "/code.user.v1.Identity/UpdatePreferences",
      type: GRPCCallType.unary
    )

    public static let loginToThirdPartyApp = GRPCMethodDescriptor(
      name: "LoginToThirdPartyApp",
      path: "/code.user.v1.Identity/LoginToThirdPartyApp",
      type: GRPCCallType.unary
    )

    public static let getLoginForThirdPartyApp = GRPCMethodDescriptor(
      name: "GetLoginForThirdPartyApp",
      path: "/code.user.v1.Identity/GetLoginForThirdPartyApp",
      type: GRPCCallType.unary
    )
  }
}

/// To build a server, implement a class that conforms to this protocol.
public protocol Code_User_V1_IdentityProvider: CallHandlerProvider {
  var interceptors: Code_User_V1_IdentityServerInterceptorFactoryProtocol? { get }

  /// LinkAccount links an owner account to the user identified and authenticated
  /// by a one-time use token.
  ///
  /// Notably, this RPC has the following side effects:
  ///   * A new user is automatically created if one doesn't exist.
  ///   * Server will create a new data container for at least every unique
  ///     owner account linked to the user.
  func linkAccount(request: Code_User_V1_LinkAccountRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_User_V1_LinkAccountResponse>

  /// UnlinkAccount removes links from an owner account. It will NOT remove
  /// existing associations between users, owner accounts and identifying
  /// features.
  ///
  /// The following associations will remain intact to ensure owner accounts
  /// can continue to be used with a consistent login experience:
  ///   * the user continues to be associated to existing owner accounts and
  ///     identifying features
  ///
  /// Client can continue mainting their current login session. Their current
  /// user and data container will remain the same.
  ///
  /// The call is guaranteed to be idempotent. It will not fail if the link is
  /// already removed by either a previous call to this RPC or by a more recent
  /// call to LinkAccount. A failure will only occur if the link between a user
  /// and the owner accout or identifying feature never existed.
  func unlinkAccount(request: Code_User_V1_UnlinkAccountRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_User_V1_UnlinkAccountResponse>

  /// GetUser gets user information given a user identifier and an owner account.
  func getUser(request: Code_User_V1_GetUserRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_User_V1_GetUserResponse>

  /// UpdatePreferences updates user preferences.
  func updatePreferences(request: Code_User_V1_UpdatePreferencesRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_User_V1_UpdatePreferencesResponse>

  /// LoginToThirdPartyApp logs a user into a third party app for a given intent
  /// ID. If the original request requires payment, then SubmitIntent must be called.
  func loginToThirdPartyApp(request: Code_User_V1_LoginToThirdPartyAppRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_User_V1_LoginToThirdPartyAppResponse>

  /// GetLoginForThirdPartyApp gets a login for a third party app from an existing
  /// request. This endpoint supports all paths where login is possible (login on payment,
  /// raw login, etc.).
  func getLoginForThirdPartyApp(request: Code_User_V1_GetLoginForThirdPartyAppRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_User_V1_GetLoginForThirdPartyAppResponse>
}

extension Code_User_V1_IdentityProvider {
  public var serviceName: Substring {
    return Code_User_V1_IdentityServerMetadata.serviceDescriptor.fullName[...]
  }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "LinkAccount":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_LinkAccountRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_LinkAccountResponse>(),
        interceptors: self.interceptors?.makeLinkAccountInterceptors() ?? [],
        userFunction: self.linkAccount(request:context:)
      )

    case "UnlinkAccount":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_UnlinkAccountRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_UnlinkAccountResponse>(),
        interceptors: self.interceptors?.makeUnlinkAccountInterceptors() ?? [],
        userFunction: self.unlinkAccount(request:context:)
      )

    case "GetUser":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_GetUserRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_GetUserResponse>(),
        interceptors: self.interceptors?.makeGetUserInterceptors() ?? [],
        userFunction: self.getUser(request:context:)
      )

    case "UpdatePreferences":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_UpdatePreferencesRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_UpdatePreferencesResponse>(),
        interceptors: self.interceptors?.makeUpdatePreferencesInterceptors() ?? [],
        userFunction: self.updatePreferences(request:context:)
      )

    case "LoginToThirdPartyApp":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_LoginToThirdPartyAppRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_LoginToThirdPartyAppResponse>(),
        interceptors: self.interceptors?.makeLoginToThirdPartyAppInterceptors() ?? [],
        userFunction: self.loginToThirdPartyApp(request:context:)
      )

    case "GetLoginForThirdPartyApp":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_GetLoginForThirdPartyAppRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_GetLoginForThirdPartyAppResponse>(),
        interceptors: self.interceptors?.makeGetLoginForThirdPartyAppInterceptors() ?? [],
        userFunction: self.getLoginForThirdPartyApp(request:context:)
      )

    default:
      return nil
    }
  }
}

#if compiler(>=5.6)

/// To implement a server, implement an object which conforms to this protocol.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Code_User_V1_IdentityAsyncProvider: CallHandlerProvider {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Code_User_V1_IdentityServerInterceptorFactoryProtocol? { get }

  /// LinkAccount links an owner account to the user identified and authenticated
  /// by a one-time use token.
  ///
  /// Notably, this RPC has the following side effects:
  ///   * A new user is automatically created if one doesn't exist.
  ///   * Server will create a new data container for at least every unique
  ///     owner account linked to the user.
  @Sendable func linkAccount(
    request: Code_User_V1_LinkAccountRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_User_V1_LinkAccountResponse

  /// UnlinkAccount removes links from an owner account. It will NOT remove
  /// existing associations between users, owner accounts and identifying
  /// features.
  ///
  /// The following associations will remain intact to ensure owner accounts
  /// can continue to be used with a consistent login experience:
  ///   * the user continues to be associated to existing owner accounts and
  ///     identifying features
  ///
  /// Client can continue mainting their current login session. Their current
  /// user and data container will remain the same.
  ///
  /// The call is guaranteed to be idempotent. It will not fail if the link is
  /// already removed by either a previous call to this RPC or by a more recent
  /// call to LinkAccount. A failure will only occur if the link between a user
  /// and the owner accout or identifying feature never existed.
  @Sendable func unlinkAccount(
    request: Code_User_V1_UnlinkAccountRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_User_V1_UnlinkAccountResponse

  /// GetUser gets user information given a user identifier and an owner account.
  @Sendable func getUser(
    request: Code_User_V1_GetUserRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_User_V1_GetUserResponse

  /// UpdatePreferences updates user preferences.
  @Sendable func updatePreferences(
    request: Code_User_V1_UpdatePreferencesRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_User_V1_UpdatePreferencesResponse

  /// LoginToThirdPartyApp logs a user into a third party app for a given intent
  /// ID. If the original request requires payment, then SubmitIntent must be called.
  @Sendable func loginToThirdPartyApp(
    request: Code_User_V1_LoginToThirdPartyAppRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_User_V1_LoginToThirdPartyAppResponse

  /// GetLoginForThirdPartyApp gets a login for a third party app from an existing
  /// request. This endpoint supports all paths where login is possible (login on payment,
  /// raw login, etc.).
  @Sendable func getLoginForThirdPartyApp(
    request: Code_User_V1_GetLoginForThirdPartyAppRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_User_V1_GetLoginForThirdPartyAppResponse
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_User_V1_IdentityAsyncProvider {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Code_User_V1_IdentityServerMetadata.serviceDescriptor
  }

  public var serviceName: Substring {
    return Code_User_V1_IdentityServerMetadata.serviceDescriptor.fullName[...]
  }

  public var interceptors: Code_User_V1_IdentityServerInterceptorFactoryProtocol? {
    return nil
  }

  public func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "LinkAccount":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_LinkAccountRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_LinkAccountResponse>(),
        interceptors: self.interceptors?.makeLinkAccountInterceptors() ?? [],
        wrapping: self.linkAccount(request:context:)
      )

    case "UnlinkAccount":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_UnlinkAccountRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_UnlinkAccountResponse>(),
        interceptors: self.interceptors?.makeUnlinkAccountInterceptors() ?? [],
        wrapping: self.unlinkAccount(request:context:)
      )

    case "GetUser":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_GetUserRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_GetUserResponse>(),
        interceptors: self.interceptors?.makeGetUserInterceptors() ?? [],
        wrapping: self.getUser(request:context:)
      )

    case "UpdatePreferences":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_UpdatePreferencesRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_UpdatePreferencesResponse>(),
        interceptors: self.interceptors?.makeUpdatePreferencesInterceptors() ?? [],
        wrapping: self.updatePreferences(request:context:)
      )

    case "LoginToThirdPartyApp":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_LoginToThirdPartyAppRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_LoginToThirdPartyAppResponse>(),
        interceptors: self.interceptors?.makeLoginToThirdPartyAppInterceptors() ?? [],
        wrapping: self.loginToThirdPartyApp(request:context:)
      )

    case "GetLoginForThirdPartyApp":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_User_V1_GetLoginForThirdPartyAppRequest>(),
        responseSerializer: ProtobufSerializer<Code_User_V1_GetLoginForThirdPartyAppResponse>(),
        interceptors: self.interceptors?.makeGetLoginForThirdPartyAppInterceptors() ?? [],
        wrapping: self.getLoginForThirdPartyApp(request:context:)
      )

    default:
      return nil
    }
  }
}

#endif // compiler(>=5.6)

public protocol Code_User_V1_IdentityServerInterceptorFactoryProtocol {

  /// - Returns: Interceptors to use when handling 'linkAccount'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeLinkAccountInterceptors() -> [ServerInterceptor<Code_User_V1_LinkAccountRequest, Code_User_V1_LinkAccountResponse>]

  /// - Returns: Interceptors to use when handling 'unlinkAccount'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeUnlinkAccountInterceptors() -> [ServerInterceptor<Code_User_V1_UnlinkAccountRequest, Code_User_V1_UnlinkAccountResponse>]

  /// - Returns: Interceptors to use when handling 'getUser'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeGetUserInterceptors() -> [ServerInterceptor<Code_User_V1_GetUserRequest, Code_User_V1_GetUserResponse>]

  /// - Returns: Interceptors to use when handling 'updatePreferences'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeUpdatePreferencesInterceptors() -> [ServerInterceptor<Code_User_V1_UpdatePreferencesRequest, Code_User_V1_UpdatePreferencesResponse>]

  /// - Returns: Interceptors to use when handling 'loginToThirdPartyApp'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeLoginToThirdPartyAppInterceptors() -> [ServerInterceptor<Code_User_V1_LoginToThirdPartyAppRequest, Code_User_V1_LoginToThirdPartyAppResponse>]

  /// - Returns: Interceptors to use when handling 'getLoginForThirdPartyApp'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeGetLoginForThirdPartyAppInterceptors() -> [ServerInterceptor<Code_User_V1_GetLoginForThirdPartyAppRequest, Code_User_V1_GetLoginForThirdPartyAppResponse>]
}

public enum Code_User_V1_IdentityServerMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "Identity",
    fullName: "code.user.v1.Identity",
    methods: [
      Code_User_V1_IdentityServerMetadata.Methods.linkAccount,
      Code_User_V1_IdentityServerMetadata.Methods.unlinkAccount,
      Code_User_V1_IdentityServerMetadata.Methods.getUser,
      Code_User_V1_IdentityServerMetadata.Methods.updatePreferences,
      Code_User_V1_IdentityServerMetadata.Methods.loginToThirdPartyApp,
      Code_User_V1_IdentityServerMetadata.Methods.getLoginForThirdPartyApp,
    ]
  )

  public enum Methods {
    public static let linkAccount = GRPCMethodDescriptor(
      name: "LinkAccount",
      path: "/code.user.v1.Identity/LinkAccount",
      type: GRPCCallType.unary
    )

    public static let unlinkAccount = GRPCMethodDescriptor(
      name: "UnlinkAccount",
      path: "/code.user.v1.Identity/UnlinkAccount",
      type: GRPCCallType.unary
    )

    public static let getUser = GRPCMethodDescriptor(
      name: "GetUser",
      path: "/code.user.v1.Identity/GetUser",
      type: GRPCCallType.unary
    )

    public static let updatePreferences = GRPCMethodDescriptor(
      name: "UpdatePreferences",
      path: "/code.user.v1.Identity/UpdatePreferences",
      type: GRPCCallType.unary
    )

    public static let loginToThirdPartyApp = GRPCMethodDescriptor(
      name: "LoginToThirdPartyApp",
      path: "/code.user.v1.Identity/LoginToThirdPartyApp",
      type: GRPCCallType.unary
    )

    public static let getLoginForThirdPartyApp = GRPCMethodDescriptor(
      name: "GetLoginForThirdPartyApp",
      path: "/code.user.v1.Identity/GetLoginForThirdPartyApp",
      type: GRPCCallType.unary
    )
  }
}
