//
//  Kado.swift
//  Code
//
//  Created by Dima Bart on 2024-08-01.
//

import Foundation

enum Kado {
    typealias JSON = [String: Any]
    
    enum Error: Swift.Error {
        case deserializationFailed
    }
    
    enum PaymentStatus: String {
        case pending
        case success
        case failed
    }
    
    enum TransferStatus: String {
        case uninitiated
        case pending
        case failed
        case settled
        case unknown
    }
    
    struct OrderStatus {
        let paymentStatus: PaymentStatus
        let transferStatus: TransferStatus
    }
    
    static func orderStatus(for orderID: String) async throws -> OrderStatus {
        let url = URL(string: "https://api.kado.money/v2/public/orders/\(orderID)")!
        let (rawJSON, _) = try await URLSession.shared.data(from: url)
        
        guard let json = try JSONSerialization.jsonObject(with: rawJSON) as? JSON else {
            throw Error.deserializationFailed
        }
        
        guard let data = json["data"] as? JSON else {
            throw Error.deserializationFailed
        }
        
        guard
            let paymentString = data["paymentStatus"] as? String,
            let paymentStatus = PaymentStatus(rawValue: paymentString)
        else {
            throw Error.deserializationFailed
        }
        
        guard
            let transferString = data["transferStatus"] as? String,
            let transferStatus = TransferStatus(rawValue: transferString)
        else {
            throw Error.deserializationFailed
        }
        
        return OrderStatus(
            paymentStatus: paymentStatus,
            transferStatus: transferStatus
        )
    }
    
    static func findOrderID(in url: URL) -> String? {
        let pathComponents = url.pathComponents
        
        guard let orderIndex = pathComponents.firstIndex(of: "order") else {
            return nil
        }
        
        let idIndex = orderIndex + 1
        
        guard idIndex < pathComponents.count else {
            return nil
        }
        
        return pathComponents[idIndex]
    }
}
