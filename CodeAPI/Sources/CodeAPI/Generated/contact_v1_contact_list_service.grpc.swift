//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: contact/v1/contact_list_service.proto
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


/// Usage: instantiate `Code_Contact_V1_ContactListClient`, then call methods of this protocol to make API calls.
public protocol Code_Contact_V1_ContactListClientProtocol: GRPCClient {
  var serviceName: String { get }
  var interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol? { get }

  func addContacts(
    _ request: Code_Contact_V1_AddContactsRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_Contact_V1_AddContactsRequest, Code_Contact_V1_AddContactsResponse>

  func removeContacts(
    _ request: Code_Contact_V1_RemoveContactsRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_Contact_V1_RemoveContactsRequest, Code_Contact_V1_RemoveContactsResponse>

  func getContacts(
    _ request: Code_Contact_V1_GetContactsRequest,
    callOptions: CallOptions?
  ) -> UnaryCall<Code_Contact_V1_GetContactsRequest, Code_Contact_V1_GetContactsResponse>
}

extension Code_Contact_V1_ContactListClientProtocol {
  public var serviceName: String {
    return "code.contact.v1.ContactList"
  }

  /// AddContacts adds a batch of contacts to a user's contact list
  ///
  /// - Parameters:
  ///   - request: Request to send to AddContacts.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func addContacts(
    _ request: Code_Contact_V1_AddContactsRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_Contact_V1_AddContactsRequest, Code_Contact_V1_AddContactsResponse> {
    return self.makeUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.addContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeAddContactsInterceptors() ?? []
    )
  }

  /// RemoveContacts removes a batch of contacts from a user's contact list
  ///
  /// - Parameters:
  ///   - request: Request to send to RemoveContacts.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func removeContacts(
    _ request: Code_Contact_V1_RemoveContactsRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_Contact_V1_RemoveContactsRequest, Code_Contact_V1_RemoveContactsResponse> {
    return self.makeUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.removeContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeRemoveContactsInterceptors() ?? []
    )
  }

  /// GetContacts gets a subset of contacts from a user's contact list
  ///
  /// - Parameters:
  ///   - request: Request to send to GetContacts.
  ///   - callOptions: Call options.
  /// - Returns: A `UnaryCall` with futures for the metadata, status and response.
  public func getContacts(
    _ request: Code_Contact_V1_GetContactsRequest,
    callOptions: CallOptions? = nil
  ) -> UnaryCall<Code_Contact_V1_GetContactsRequest, Code_Contact_V1_GetContactsResponse> {
    return self.makeUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.getContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetContactsInterceptors() ?? []
    )
  }
}

#if compiler(>=5.6)
@available(*, deprecated)
extension Code_Contact_V1_ContactListClient: @unchecked Sendable {}
#endif // compiler(>=5.6)

@available(*, deprecated, renamed: "Code_Contact_V1_ContactListNIOClient")
public final class Code_Contact_V1_ContactListClient: Code_Contact_V1_ContactListClientProtocol {
  private let lock = Lock()
  private var _defaultCallOptions: CallOptions
  private var _interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol?
  public let channel: GRPCChannel
  public var defaultCallOptions: CallOptions {
    get { self.lock.withLock { return self._defaultCallOptions } }
    set { self.lock.withLockVoid { self._defaultCallOptions = newValue } }
  }
  public var interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol? {
    get { self.lock.withLock { return self._interceptors } }
    set { self.lock.withLockVoid { self._interceptors = newValue } }
  }

  /// Creates a client for the code.contact.v1.ContactList service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self._defaultCallOptions = defaultCallOptions
    self._interceptors = interceptors
  }
}

public struct Code_Contact_V1_ContactListNIOClient: Code_Contact_V1_ContactListClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol?

  /// Creates a client for the code.contact.v1.ContactList service.
  ///
  /// - Parameters:
  ///   - channel: `GRPCChannel` to the service host.
  ///   - defaultCallOptions: Options to use for each service call if the user doesn't provide them.
  ///   - interceptors: A factory providing interceptors for each RPC.
  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

#if compiler(>=5.6)
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Code_Contact_V1_ContactListAsyncClientProtocol: GRPCClient {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol? { get }

  func makeAddContactsCall(
    _ request: Code_Contact_V1_AddContactsRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_Contact_V1_AddContactsRequest, Code_Contact_V1_AddContactsResponse>

  func makeRemoveContactsCall(
    _ request: Code_Contact_V1_RemoveContactsRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_Contact_V1_RemoveContactsRequest, Code_Contact_V1_RemoveContactsResponse>

  func makeGetContactsCall(
    _ request: Code_Contact_V1_GetContactsRequest,
    callOptions: CallOptions?
  ) -> GRPCAsyncUnaryCall<Code_Contact_V1_GetContactsRequest, Code_Contact_V1_GetContactsResponse>
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Contact_V1_ContactListAsyncClientProtocol {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Code_Contact_V1_ContactListClientMetadata.serviceDescriptor
  }

  public var interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol? {
    return nil
  }

  public func makeAddContactsCall(
    _ request: Code_Contact_V1_AddContactsRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_Contact_V1_AddContactsRequest, Code_Contact_V1_AddContactsResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.addContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeAddContactsInterceptors() ?? []
    )
  }

  public func makeRemoveContactsCall(
    _ request: Code_Contact_V1_RemoveContactsRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_Contact_V1_RemoveContactsRequest, Code_Contact_V1_RemoveContactsResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.removeContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeRemoveContactsInterceptors() ?? []
    )
  }

  public func makeGetContactsCall(
    _ request: Code_Contact_V1_GetContactsRequest,
    callOptions: CallOptions? = nil
  ) -> GRPCAsyncUnaryCall<Code_Contact_V1_GetContactsRequest, Code_Contact_V1_GetContactsResponse> {
    return self.makeAsyncUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.getContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetContactsInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Contact_V1_ContactListAsyncClientProtocol {
  public func addContacts(
    _ request: Code_Contact_V1_AddContactsRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_Contact_V1_AddContactsResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.addContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeAddContactsInterceptors() ?? []
    )
  }

  public func removeContacts(
    _ request: Code_Contact_V1_RemoveContactsRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_Contact_V1_RemoveContactsResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.removeContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeRemoveContactsInterceptors() ?? []
    )
  }

  public func getContacts(
    _ request: Code_Contact_V1_GetContactsRequest,
    callOptions: CallOptions? = nil
  ) async throws -> Code_Contact_V1_GetContactsResponse {
    return try await self.performAsyncUnaryCall(
      path: Code_Contact_V1_ContactListClientMetadata.Methods.getContacts.path,
      request: request,
      callOptions: callOptions ?? self.defaultCallOptions,
      interceptors: self.interceptors?.makeGetContactsInterceptors() ?? []
    )
  }
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct Code_Contact_V1_ContactListAsyncClient: Code_Contact_V1_ContactListAsyncClientProtocol {
  public var channel: GRPCChannel
  public var defaultCallOptions: CallOptions
  public var interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol?

  public init(
    channel: GRPCChannel,
    defaultCallOptions: CallOptions = CallOptions(),
    interceptors: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol? = nil
  ) {
    self.channel = channel
    self.defaultCallOptions = defaultCallOptions
    self.interceptors = interceptors
  }
}

#endif // compiler(>=5.6)

public protocol Code_Contact_V1_ContactListClientInterceptorFactoryProtocol: GRPCSendable {

  /// - Returns: Interceptors to use when invoking 'addContacts'.
  func makeAddContactsInterceptors() -> [ClientInterceptor<Code_Contact_V1_AddContactsRequest, Code_Contact_V1_AddContactsResponse>]

  /// - Returns: Interceptors to use when invoking 'removeContacts'.
  func makeRemoveContactsInterceptors() -> [ClientInterceptor<Code_Contact_V1_RemoveContactsRequest, Code_Contact_V1_RemoveContactsResponse>]

  /// - Returns: Interceptors to use when invoking 'getContacts'.
  func makeGetContactsInterceptors() -> [ClientInterceptor<Code_Contact_V1_GetContactsRequest, Code_Contact_V1_GetContactsResponse>]
}

public enum Code_Contact_V1_ContactListClientMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "ContactList",
    fullName: "code.contact.v1.ContactList",
    methods: [
      Code_Contact_V1_ContactListClientMetadata.Methods.addContacts,
      Code_Contact_V1_ContactListClientMetadata.Methods.removeContacts,
      Code_Contact_V1_ContactListClientMetadata.Methods.getContacts,
    ]
  )

  public enum Methods {
    public static let addContacts = GRPCMethodDescriptor(
      name: "AddContacts",
      path: "/code.contact.v1.ContactList/AddContacts",
      type: GRPCCallType.unary
    )

    public static let removeContacts = GRPCMethodDescriptor(
      name: "RemoveContacts",
      path: "/code.contact.v1.ContactList/RemoveContacts",
      type: GRPCCallType.unary
    )

    public static let getContacts = GRPCMethodDescriptor(
      name: "GetContacts",
      path: "/code.contact.v1.ContactList/GetContacts",
      type: GRPCCallType.unary
    )
  }
}

/// To build a server, implement a class that conforms to this protocol.
public protocol Code_Contact_V1_ContactListProvider: CallHandlerProvider {
  var interceptors: Code_Contact_V1_ContactListServerInterceptorFactoryProtocol? { get }

  /// AddContacts adds a batch of contacts to a user's contact list
  func addContacts(request: Code_Contact_V1_AddContactsRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_Contact_V1_AddContactsResponse>

  /// RemoveContacts removes a batch of contacts from a user's contact list
  func removeContacts(request: Code_Contact_V1_RemoveContactsRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_Contact_V1_RemoveContactsResponse>

  /// GetContacts gets a subset of contacts from a user's contact list
  func getContacts(request: Code_Contact_V1_GetContactsRequest, context: StatusOnlyCallContext) -> EventLoopFuture<Code_Contact_V1_GetContactsResponse>
}

extension Code_Contact_V1_ContactListProvider {
  public var serviceName: Substring {
    return Code_Contact_V1_ContactListServerMetadata.serviceDescriptor.fullName[...]
  }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  public func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "AddContacts":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Contact_V1_AddContactsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Contact_V1_AddContactsResponse>(),
        interceptors: self.interceptors?.makeAddContactsInterceptors() ?? [],
        userFunction: self.addContacts(request:context:)
      )

    case "RemoveContacts":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Contact_V1_RemoveContactsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Contact_V1_RemoveContactsResponse>(),
        interceptors: self.interceptors?.makeRemoveContactsInterceptors() ?? [],
        userFunction: self.removeContacts(request:context:)
      )

    case "GetContacts":
      return UnaryServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Contact_V1_GetContactsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Contact_V1_GetContactsResponse>(),
        interceptors: self.interceptors?.makeGetContactsInterceptors() ?? [],
        userFunction: self.getContacts(request:context:)
      )

    default:
      return nil
    }
  }
}

#if compiler(>=5.6)

/// To implement a server, implement an object which conforms to this protocol.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public protocol Code_Contact_V1_ContactListAsyncProvider: CallHandlerProvider {
  static var serviceDescriptor: GRPCServiceDescriptor { get }
  var interceptors: Code_Contact_V1_ContactListServerInterceptorFactoryProtocol? { get }

  /// AddContacts adds a batch of contacts to a user's contact list
  @Sendable func addContacts(
    request: Code_Contact_V1_AddContactsRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_Contact_V1_AddContactsResponse

  /// RemoveContacts removes a batch of contacts from a user's contact list
  @Sendable func removeContacts(
    request: Code_Contact_V1_RemoveContactsRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_Contact_V1_RemoveContactsResponse

  /// GetContacts gets a subset of contacts from a user's contact list
  @Sendable func getContacts(
    request: Code_Contact_V1_GetContactsRequest,
    context: GRPCAsyncServerCallContext
  ) async throws -> Code_Contact_V1_GetContactsResponse
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Code_Contact_V1_ContactListAsyncProvider {
  public static var serviceDescriptor: GRPCServiceDescriptor {
    return Code_Contact_V1_ContactListServerMetadata.serviceDescriptor
  }

  public var serviceName: Substring {
    return Code_Contact_V1_ContactListServerMetadata.serviceDescriptor.fullName[...]
  }

  public var interceptors: Code_Contact_V1_ContactListServerInterceptorFactoryProtocol? {
    return nil
  }

  public func handle(
    method name: Substring,
    context: CallHandlerContext
  ) -> GRPCServerHandlerProtocol? {
    switch name {
    case "AddContacts":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Contact_V1_AddContactsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Contact_V1_AddContactsResponse>(),
        interceptors: self.interceptors?.makeAddContactsInterceptors() ?? [],
        wrapping: self.addContacts(request:context:)
      )

    case "RemoveContacts":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Contact_V1_RemoveContactsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Contact_V1_RemoveContactsResponse>(),
        interceptors: self.interceptors?.makeRemoveContactsInterceptors() ?? [],
        wrapping: self.removeContacts(request:context:)
      )

    case "GetContacts":
      return GRPCAsyncServerHandler(
        context: context,
        requestDeserializer: ProtobufDeserializer<Code_Contact_V1_GetContactsRequest>(),
        responseSerializer: ProtobufSerializer<Code_Contact_V1_GetContactsResponse>(),
        interceptors: self.interceptors?.makeGetContactsInterceptors() ?? [],
        wrapping: self.getContacts(request:context:)
      )

    default:
      return nil
    }
  }
}

#endif // compiler(>=5.6)

public protocol Code_Contact_V1_ContactListServerInterceptorFactoryProtocol {

  /// - Returns: Interceptors to use when handling 'addContacts'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeAddContactsInterceptors() -> [ServerInterceptor<Code_Contact_V1_AddContactsRequest, Code_Contact_V1_AddContactsResponse>]

  /// - Returns: Interceptors to use when handling 'removeContacts'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeRemoveContactsInterceptors() -> [ServerInterceptor<Code_Contact_V1_RemoveContactsRequest, Code_Contact_V1_RemoveContactsResponse>]

  /// - Returns: Interceptors to use when handling 'getContacts'.
  ///   Defaults to calling `self.makeInterceptors()`.
  func makeGetContactsInterceptors() -> [ServerInterceptor<Code_Contact_V1_GetContactsRequest, Code_Contact_V1_GetContactsResponse>]
}

public enum Code_Contact_V1_ContactListServerMetadata {
  public static let serviceDescriptor = GRPCServiceDescriptor(
    name: "ContactList",
    fullName: "code.contact.v1.ContactList",
    methods: [
      Code_Contact_V1_ContactListServerMetadata.Methods.addContacts,
      Code_Contact_V1_ContactListServerMetadata.Methods.removeContacts,
      Code_Contact_V1_ContactListServerMetadata.Methods.getContacts,
    ]
  )

  public enum Methods {
    public static let addContacts = GRPCMethodDescriptor(
      name: "AddContacts",
      path: "/code.contact.v1.ContactList/AddContacts",
      type: GRPCCallType.unary
    )

    public static let removeContacts = GRPCMethodDescriptor(
      name: "RemoveContacts",
      path: "/code.contact.v1.ContactList/RemoveContacts",
      type: GRPCCallType.unary
    )

    public static let getContacts = GRPCMethodDescriptor(
      name: "GetContacts",
      path: "/code.contact.v1.ContactList/GetContacts",
      type: GRPCCallType.unary
    )
  }
}
