//
//  ContactsService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2022 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC

class ContactsService: CodeService<Code_Contact_V1_ContactListNIOClient> {
    
    func uploadContacts(containerID: ID, phoneNumbers: [Phone], owner: KeyPair, completion: @escaping (Result<Void, Error>) -> Void) {
        trace(.send, components: "Container: \(containerID)")

        var request = Code_Contact_V1_AddContactsRequest()
        request.containerID = containerID.codeContainerID
        request.contacts = phoneNumbers.map { $0.codePhoneNumber }
        request.ownerAccountID = owner.publicKey.codeAccountID
        request.signature = request.sign(with: owner)

        let call = service.addContacts(request)
        call.handle(on: queue) { response in
            trace(.success, components: "Container: \(containerID)")
            if response.result == .ok {
                completion(.success(()))
            } else {
                completion(.failure(ErrorGeneric.unknown))
            }

        } failure: { error in
            completion(.failure(ErrorGeneric.unknown))
        }
    }
    
    func fetchAppContacts(containerID: ID, owner: KeyPair, completion: @escaping (Result<[PhoneDescription], Error>) -> Void) {
        trace(.send, components: "Container: \(containerID)")

        var request = Code_Contact_V1_GetContactsRequest()
        request.containerID = containerID.codeContainerID
        request.ownerAccountID = owner.publicKey.codeAccountID
        request.includeOnlyInAppContacts = true
        request.signature = request.sign(with: owner)

        let call = service.getContacts(request)
        call.handle(on: queue) { response in
            trace(.success, components: "Container: \(containerID)")
            if response.result == .ok {
                let phoneDescriptions = response.contacts.compactMap { PhoneDescription($0) }
                completion(.success(phoneDescriptions))
            } else {
                completion(.failure(ErrorGeneric.unknown))
            }

        } failure: { error in
            completion(.failure(ErrorGeneric.unknown))
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Contact_V1_ContactListClientInterceptorFactoryProtocol {
    func makeAddContactsInterceptors() -> [ClientInterceptor<Code_Contact_V1_AddContactsRequest, Code_Contact_V1_AddContactsResponse>] {
        makeInterceptors()
    }
    
    func makeRemoveContactsInterceptors() -> [ClientInterceptor<Code_Contact_V1_RemoveContactsRequest, Code_Contact_V1_RemoveContactsResponse>] {
        makeInterceptors()
    }
    
    func makeGetContactsInterceptors() -> [ClientInterceptor<Code_Contact_V1_GetContactsRequest, Code_Contact_V1_GetContactsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Contact_V1_ContactListNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
