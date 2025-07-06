//
//  MCPRequest.swift
//  mcpSwift
//
//  Created on 20/6/2025.
//  License MIT
//

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// A request message.
public struct MCPRequest<M: MCPMethod>: Hashable, Identifiable, Codable, Sendable {
    /// The request ID.
    public let id: MCPID
    /// The method name.
    public let method: String
    /// The request parameters.
    public let params: M.Parameters

    init(id: MCPID = .random, method: String, params: M.Parameters) {
        self.id = id
        self.method = method
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MCPVersion.jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encode(params, forKey: .params)
    }
}

extension MCPRequest {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == MCPVersion.jsonrpc else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc, in: container, debugDescription: "Invalid JSON-RPC version")
        }
        id = try container.decode(ID.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)

        if M.Parameters.self is NotRequired.Type {
            // For NotRequired parameters, use decodeIfPresent or init()
            params =
                (try container.decodeIfPresent(M.Parameters.self, forKey: .params)
                    ?? (M.Parameters.self as! NotRequired.Type).init() as! M.Parameters)
        } else if let value = try? container.decode(M.Parameters.self, forKey: .params) {
            // If params exists and can be decoded, use it
            params = value
        } else if !container.contains(.params)
            || (try? container.decodeNil(forKey: .params)) == true
        {
            // If params is missing or explicitly null, use Empty for Empty parameters
            // or throw for non-Empty parameters
            if M.Parameters.self == Empty.self {
                params = Empty() as! M.Parameters
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Missing required params field"))
            }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid params field"))
        }
    }
}

/// A type-erased request for request/response handling
typealias AnyMCPRequest = MCPRequest<AnyMCPMethod>

extension AnyMCPRequest {
    init<T: MCPMethod>(_ request: MCPRequest<T>) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(request)
        self = try decoder.decode(AnyMCPRequest.self, from: data)
    }
}

/// A box for request handlers that can be type-erased
class MCPRequestHandlerBox: @unchecked Sendable {
    func callAsFunction(_ request: AnyMCPRequest) async throws -> AnyMCPResponse {
        fatalError("Must override")
    }
}

/// A typed request handler that can be used to handle requests of a specific type
final class TypedMCPRequestHandler<M: MCPMethod>: MCPRequestHandlerBox, @unchecked Sendable {
    private let _handle: @Sendable (MCPRequest<M>) async throws -> MCPResponse<M>

    init(_ handler: @escaping @Sendable (MCPRequest<M>) async throws -> MCPResponse<M>) {
        self._handle = handler
        super.init()
    }

    override func callAsFunction(_ request: AnyMCPRequest) async throws -> AnyMCPResponse {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Create a concrete request from the type-erased one
        let data = try encoder.encode(request)
        let request = try decoder.decode(MCPRequest<M>.self, from: data)

        // Handle with concrete type
        let response = try await _handle(request)

        // Convert result to AnyMethod response
        switch response.result {
        case .success(let result):
            let resultData = try encoder.encode(result)
            let resultValue = try decoder.decode(MCPValue.self, from: resultData)
            return MCPResponse(id: response.id, result: resultValue)
        case .failure(let error):
            return MCPResponse(id: response.id, error: error)
        }
    }
}
