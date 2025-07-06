//
//  MCPPing.swift
//  sourced from swift-sdk
//  modified for mcpSwift
//  modify date 18/06/2025
//
//  License MIT
//

/// The Model Context Protocol includes an optional ping mechanism that allows either party to verify that their counterpart is still responsive and the connection is alive.
/// - SeeAlso: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/utilities/ping
public enum MCPPing: MCPMethod {
    public static let name: String = "ping"
}
