//
//  HistoricalTransaction.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct HistoricalTransaction: Codable, Equatable {
    
    public var id: ID
    public var paymentType: PaymentType
    public var date: Date
    public var kinAmount: KinAmount
    public var nativeAmount: Decimal
    public var isDeposit: Bool
    public var isWithdrawal: Bool
    public var isRemoteSend: Bool
    public var isReturned: Bool
    public var isMicroPayment: Bool
    public var airdropType: AirdropType?
    
    public init(id: ID, paymentType: PaymentType, date: Date, kinAmount: KinAmount, nativeAmount: Decimal, isDeposit: Bool, isWithdrawal: Bool, isRemoteSend: Bool, isReturned: Bool, isMicroPayment: Bool, airdropType: AirdropType?) {
        self.id             = id
        self.paymentType    = paymentType
        self.date           = date
        self.kinAmount      = kinAmount
        self.nativeAmount   = nativeAmount
        self.isDeposit      = isDeposit
        self.isWithdrawal   = isWithdrawal
        self.isRemoteSend   = isRemoteSend
        self.isReturned     = isReturned
        self.isMicroPayment = isMicroPayment
        self.airdropType    = airdropType
    }
}

public enum PaymentType: Int, Codable, Equatable {
    case unknown
    case send
    case receive
}
