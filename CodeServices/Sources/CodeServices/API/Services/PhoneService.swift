//
//  PhoneService.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI
import Combine
import GRPC
import DeviceCheck

class PhoneService: CodeService<Code_Phone_V1_PhoneVerificationNIOClient> {
    
    func sendCode(phone: Phone, completion: @escaping (Result<Void, ErrorSendCode>) -> Void) {
        trace(.send, components: "Phone: \(phone)")
        
        createVerificationCodeRequest(phone: phone) { request in
            let call = self.service.sendVerificationCode(request)
            call.handle(on: self.queue) { response in
                let error = ErrorSendCode(rawValue: response.result.rawValue) ?? .unknown
                if error == .ok {
                    trace(.success, components: "Phone: \(phone)")
                    completion(.success(()))
                } else {
                    trace(.failure, components: "Phone: \(phone), Error: \(error)")
                    completion(.failure(error))
                }
                
            } failure: { error in
                completion(.failure(.unknown))
            }
        }
    }
    
    private func createVerificationCodeRequest(phone: Phone, completion: @escaping (Code_Phone_V1_SendVerificationCodeRequest) -> Void) {
        let device = DCDevice.current
        if device.isSupported {
            device.generateToken { token, error in
                completion(.with {
                    $0.phoneNumber = phone.codePhoneNumber
                    $0.deviceToken = .with { $0.value = token?.base64EncodedString() ?? "" }
                })
            }
        } else {
            completion(.with {
                $0.phoneNumber = phone.codePhoneNumber
                $0.deviceToken = .with { $0.value = "" }
            })
        }
    }
    
    func validate(phone: Phone, code: String, completion: @escaping (Result<Void, ErrorValidateCode>) -> Void) {
        trace(.send, components: "Phone: \(phone)", "Code: \(code)")
        
        var request = Code_Phone_V1_CheckVerificationCodeRequest()
        request.phoneNumber = phone.codePhoneNumber
        request.code = code.codeVerificationCode
        
        let call = service.checkVerificationCode(request)
        call.handle(on: queue) { response in
            let error = ErrorValidateCode(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok {
                trace(.success, components: "Phone: \(phone)", "Code: \(code)")
                completion(.success(()))
            } else {
                trace(.failure, components: "Phone: \(phone)", "Code: \(code), Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            trace(.failure, components: "Phone: \(phone)", "Code: \(code)")
            completion(.failure(.unknown))
        }
    }
    
    func fetchAssociatedPhoneNumber(owner: KeyPair, completion: @escaping (Result<PhoneLink, ErrorFetchAssociatedPhone>) -> Void) {
        trace(.send, components: "Owner: \(owner.publicKey.base58)")
        
        var request = Code_Phone_V1_GetAssociatedPhoneNumberRequest()
        request.ownerAccountID = owner.publicKey.codeAccountID
        request.signature = request.sign(with: owner)
        
        let call = service.getAssociatedPhoneNumber(request)
        call.handle(on: queue) { response in
            let error = ErrorFetchAssociatedPhone(rawValue: response.result.rawValue) ?? .unknown
            if error == .ok, let phone = Phone(response.phoneNumber.value) {
                let status = PhoneLink(phone: phone, isLinked: response.isLinked)
                trace(.success, components: "Owner: \(owner.publicKey.base58)", "Phone: \(response.phoneNumber.value)")
                completion(.success(status))
            } else {
                trace(.failure, components: "Owner: \(owner.publicKey.base58)", "Phone: \(response.phoneNumber.value), Error: \(error)")
                completion(.failure(error))
            }
            
        } failure: { error in
            completion(.failure(.unknown))
        }
    }
}

// MARK: - Errors -

public enum ErrorSendCode: Int, Error {
    case ok
    case notInvited
    case rateLimited
    case invalidPhoneNumber
    case unsupportedPhoneNumber
    case unsupportedCountry
    case unsupportedDevice
    case unknown = -1
}

public enum ErrorValidateCode: Int, Error {
    case ok
    case invalidCode
    case noVerification
    case rateLimited
    case unknown = -1
}

public enum ErrorFetchAssociatedPhone: Int, Error {
    case ok
    case notFound
    case notInvited
    case unlockedTimelock
    case unknown = -1
}

// MARK: - Interceptors -

extension InterceptorFactory: Code_Phone_V1_PhoneVerificationClientInterceptorFactoryProtocol {
    func makeSendVerificationCodeInterceptors() -> [ClientInterceptor<Code_Phone_V1_SendVerificationCodeRequest, Code_Phone_V1_SendVerificationCodeResponse>] {
        makeInterceptors()
    }
    
    func makeCheckVerificationCodeInterceptors() -> [ClientInterceptor<Code_Phone_V1_CheckVerificationCodeRequest, Code_Phone_V1_CheckVerificationCodeResponse>] {
        makeInterceptors()
    }
    
    func makeGetAssociatedPhoneNumberInterceptors() -> [ClientInterceptor<Code_Phone_V1_GetAssociatedPhoneNumberRequest, Code_Phone_V1_GetAssociatedPhoneNumberResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Code_Phone_V1_PhoneVerificationNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: CallOptions(), interceptors: InterceptorFactory())
    }
}
