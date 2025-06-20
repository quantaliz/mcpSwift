//
//  Lifecycle.swift
//  sourced from swift-sdk
//  modified for mcpSwift
//  modify date 18/06/2025
//
//  License MIT
//

/// The initialization phase MUST be the first interaction between client and server.
/// During this phase, the client and server:
/// - Establish protocol version compatibility
/// - Exchange and negotiate capabilities
/// - Share implementation details
///
/// - SeeAlso: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle/#initialization
public enum MCPInitialize: MCPMethod {
    public static let name: String = "initialize"

    public struct Parameters: Hashable, Codable, Sendable {
        public let protocolVersion: String
        public let capabilities: MCPClient.Capabilities
        public let clientInfo: MCPClient.Info

        public init(
            protocolVersion: String = MCPVersion.latest,
            capabilities: MCPClient.Capabilities,
            clientInfo: MCPClient.Info
        ) {
            self.protocolVersion = protocolVersion
            self.capabilities = capabilities
            self.clientInfo = clientInfo
        }

        private enum CodingKeys: String, CodingKey {
            case protocolVersion, capabilities, clientInfo
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            protocolVersion =
                try container.decodeIfPresent(String.self, forKey: .protocolVersion)
                ?? MCPVersion.latest
            capabilities =
                try container.decodeIfPresent(MCPClient.Capabilities.self, forKey: .capabilities)
                ?? .init()
            clientInfo =
                try container.decodeIfPresent(MCPClient.Info.self, forKey: .clientInfo)
                ?? .init(name: "unknown", version: "0.0.0")
        }
    }

    public struct Result: Hashable, Codable, Sendable {
        public let protocolVersion: String
        public let capabilities: Server.Capabilities
        public let serverInfo: Server.Info
        public let instructions: String?
    }
}

/// After successful initialization, the client MUST send an initialized notification to indicate it is ready to begin normal operations.
/// - SeeAlso: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/lifecycle/#initialization
public struct MCPInitializeNotification: MCPNotification {
    public static let name: String = "notifications/initialized"
}
