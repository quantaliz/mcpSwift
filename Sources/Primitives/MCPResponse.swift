//
//  MCPResponse.swift
//  mcpSwift
//
//  Created on 20/6/2025.
//  License MIT
//

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// A response message.
public struct MCPResponse<M: MCPMethod>: Hashable, Identifiable, Codable, Sendable {
    /// The response ID.
    public let id: MCPID
    /// The response result.
    public let result: Swift.Result<M.Result, MCPError>

    public init(id: MCPID, result: M.Result) {
        self.id = id
        self.result = .success(result)
    }

    public init(id: MCPID, error: MCPError) {
        self.id = id
        self.result = .failure(error)
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(MCPVersion.jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        switch result {
        case .success(let result):
            try container.encode(result, forKey: .result)
        case .failure(let error):
            try container.encode(error, forKey: .error)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == MCPVersion.jsonrpc else {
            throw DecodingError.dataCorruptedError(
                forKey: .jsonrpc, in: container, debugDescription: "Invalid JSON-RPC version")
        }
        id = try container.decode(ID.self, forKey: .id)
        if let result = try? container.decode(M.Result.self, forKey: .result) {
            self.result = .success(result)
        } else if let error = try? container.decode(MCPError.self, forKey: .error) {
            self.result = .failure(error)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Invalid response"))
        }
    }
}

/// A type-erased response for request/response handling
typealias AnyMCPResponse = MCPResponse<AnyMCPMethod>

extension AnyMCPResponse {
    init<T: MCPMethod>(_ response: MCPResponse<T>) throws {
        // Instead of re-encoding/decoding which might double-wrap the error,
        // directly transfer the properties
        self.id = response.id
        switch response.result {
        case .success(let result):
            // For success, we still need to convert the result to a MCPValue
            let data = try JSONEncoder().encode(result)
            let resultValue = try JSONDecoder().decode(MCPValue.self, from: data)
            self.result = .success(resultValue)
        case .failure(let error):
            // Keep the original error without re-encoding/decoding
            self.result = .failure(error)
        }
    }
}
