//
//  PageQuery.swift
//  FlipchatServices
//
//  Created by Dima Bart on 2024-10-23.
//

import Foundation
import FlipchatAPI

public struct PageQuery {
    
    public var pageSize: Int = 1024
    public var order: Order
    public var pagingToken: UUID?

    public init(order: Order = .asc, pagingToken: UUID? = nil, pageSize: Int = 100) {
        self.order = order
        self.pagingToken = pagingToken
        self.pageSize = pageSize
    }
    
    var protoQueryOptions: Flipchat_Common_V1_QueryOptions {
        .with {
            $0.pageSize = Int64(pageSize)
            $0.order    = order.protoOrder
            
            if let pagingToken {
                $0.pagingToken = .with { $0.value = pagingToken.data }
            }
        }
    }
}

// MARK: - Order -

extension PageQuery {
    public enum Order {
        
        case asc
        case desc
        
        var protoOrder: Flipchat_Common_V1_QueryOptions.Order {
            switch self {
            case .asc:  return .asc
            case .desc: return .desc
            }
        }
    }
}

// MARK: - CustomStringConvertible -

extension PageQuery: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        let size  = "\(pageSize)"
        let token = pagingToken?.data.hexEncodedString() ?? "0"
        let order = "\(order == .asc ? "asc" : "desc")"
        return [token, size, order].joined(separator: ":")
    }
    
    public var debugDescription: String {
        description
    }
}
