//
//  MCPMethod.swift
//  mcpSwift
//
//  Created on 20/6/2025.
//  License MIT
//

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

public protocol NotRequired {
    init()
}

public struct Empty: NotRequired, Hashable, Codable, Sendable {
    public init() {}
}

/// A method that can be used to send requests and receive responses.
public protocol MCPMethod {
    /// The parameters of the method.
    associatedtype Parameters: Codable, Hashable, Sendable = Empty
    /// The result of the method.
    associatedtype Result: Codable, Hashable, Sendable = Empty
    /// The name of the method.
    static var name: String { get }
}

/// Type-erased method for request/response handling
struct AnyMCPMethod: MCPMethod, Sendable {
    static var name: String { "" }
    typealias Parameters = MCPValue
    typealias Result = MCPValue
}

extension MCPMethod where Parameters == Empty {
    public static func request(id: MCPID = .random) -> MCPRequest<Self> {
        MCPRequest(id: id, method: name, params: Empty())
    }
}

extension MCPMethod where Result == Empty {
    public static func response(id: MCPID) -> MCPResponse<Self> {
        MCPResponse(id: id, result: Empty())
    }
}

extension MCPMethod {
    /// Create a request with the given parameters.
    public static func request(id: MCPID = .random, _ parameters: Self.Parameters) -> MCPRequest<Self>
    {
        MCPRequest(id: id, method: name, params: parameters)
    }

    /// Create a response with the given result.
    public static func response(id: MCPID, result: Self.Result) -> MCPResponse<Self> {
        MCPResponse(id: id, result: result)
    }

    /// Create a response with the given error.
    public static func response(id: MCPID, error: MCPError) -> MCPResponse<Self> {
        MCPResponse(id: id, error: error)
    }
}
