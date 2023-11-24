//
//  InviteService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import GRPC
import NIO

class InviteService: CodeService<Code_Invite_V2_InviteNIOClient> {
    
    func redeem(inviteCode: String, for phoneNumber: Phone, completion: @escaping (Result<Void, ErrorSendInvite>) -> Void) {
        trace(.send, components: "Redeem code: \(inviteCode)", "Phone to whitelist: \(phoneNumber)")
        whitelist(phoneNumber: phoneNumber, inviteSource: .inviteCode(inviteCode), completion: completion)
    }
    
    func whitelist(phoneNumber: Phone, userID: ID, completion: @escaping (Result<Void, ErrorSendInvite>) -> Void) {
        trace(.send, components: "Phone to whitelist: \(phoneNumber)", "From User ID: \(userID)")
        whitelist(phoneNumber: phoneNumber, inviteSource: .user(userID), completion: completion)
    }
    
    private func whitelist(phoneNumber: Phone, inviteSource: InviteSource, completion: @escaping (Result<Void, ErrorSendInvite>) -> Void) {
        
        let request = Code_Invite_V2_InvitePhoneNumberRequest.with {
            $0.source = inviteSource.source
            $0.receiver = phoneNumber.codePhoneNumber
        }
    
        let call = service.invitePhoneNumber(request)
        call.handle(on: queue) { response in
            let status = ErrorSendInvite(rawValue: response.result.rawValue) ?? .unknown
            if status == .ok {
                trace(.success, components: "Status: \(status)")
                completion(.success(()))
            } else {
                trace(.failure, components: "Status: \(status)")
                completion(.failure(status))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
    
    func fetchInviteCount(userID: ID, completion: @escaping (Result<Int, Error>) -> Void) {
        trace(.send, components: "User ID: \(userID)")
        
        let request = Code_Invite_V2_GetInviteCountRequest.with {
            $0.userID = userID.codeUserID
        }
    
        let call = service.getInviteCount(request)
        call.handle(on: queue) { response in
            // TODO: Handle response errors (for backwards compatibility)
            trace(.success, components: "\(response.inviteCount) invites")
            completion(.success(Int(response.inviteCount)))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
    
    func fetchInviteStatus(userID: ID, completion: @escaping (Result<InvitationStatus, Error>) -> Void) {
        trace(.send, components: "User ID: \(userID)")
        
        let request = Code_Invite_V2_GetInvitationStatusRequest.with {
            $0.userID = userID.codeUserID
        }
    
        let call = service.getInvitationStatus(request)
        call.handle(on: queue) { response in
            let status = InvitationStatus(rawValue: response.status.rawValue) ?? .notInvited
            trace(.success, components: "Invitation status: \(status)")
            completion(.success(status))
            
        } failure: { error in
            completion(.failure(error))
        }
    }
}

// MARK: - InviteSource -

private extension InviteService {
    enum InviteSource {
        
        case user(ID)
        case inviteCode(String)
        
        var source: Code_Invite_V2_InvitePhoneNumberRequest.OneOf_Source {
            switch self {
            case .user(let id):
                return .user(id.codeUserID)
            case .inviteCode(let code):
                return .inviteCode(.with { $0.value = code })
            }
        }
    }
}

// MARK: - Errors -

public enum ErrorSendInvite: Int, Error {
    case ok
    case inviteCountExceeded
    case alreadyInvited
    case userNotInvited
    case invalidReceiverPhoneNumber
    case inviteCodeNotFound
    case inviteCodeRevoked
    case inviteCodeExpired
    case unknown = -1
}

public enum InvitationStatus: Int {
    case notInvited
    case invited
    case registered
    case revoked
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Invite_V2_InviteClientInterceptorFactoryProtocol {
    func makeGetInvitationStatusInterceptors() -> [ClientInterceptor<Code_Invite_V2_GetInvitationStatusRequest, Code_Invite_V2_GetInvitationStatusResponse>] {
        makeInterceptors()
    }
    
    func makeGetInviteCountInterceptors() -> [ClientInterceptor<Code_Invite_V2_GetInviteCountRequest, Code_Invite_V2_GetInviteCountResponse>] {
        makeInterceptors()
    }
    
    func makeInvitePhoneNumberInterceptors() -> [ClientInterceptor<Code_Invite_V2_InvitePhoneNumberRequest, Code_Invite_V2_InvitePhoneNumberResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Invite_V2_InviteNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
