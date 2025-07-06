//
//  Notification+MCPMessage.swift
//  mcpSwift
//
//  Created on 20/6/2025.
//  License MIT
//

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder


/// A notification message.
public protocol MCPNotification: Hashable, Codable, Sendable {
    /// The parameters of the notification.
    associatedtype Parameters: Hashable, Codable, Sendable = Empty
    /// The name of the notification.
    static var name: String { get }
}

/// A type-erased notification for message handling
struct AnyMCPNotification: MCPNotification, Sendable {
    static var name: String { "" }
    typealias Parameters = MCPValue
}

extension AnyMCPNotification {
    init(_ notification: some MCPNotification) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(notification)
        self = try decoder.decode(AnyMCPNotification.self, from: data)
    }
}

extension MCPNotification where Parameters == Empty {
    /// Create a message with empty parameters.
    public static func message() -> MCPMessage<Self> {
        MCPMessage(method: name, params: Empty())
    }
}

extension MCPNotification {
    /// Create a message with the given parameters.
    public static func message(_ parameters: Parameters) -> MCPMessage<Self> {
        MCPMessage(method: name, params: parameters)
    }
}

/// A box for notification handlers that can be type-erased
class MCPNotificationHandlerBox: @unchecked Sendable {
    func callAsFunction(_ notification: MCPMessage<AnyMCPNotification>) async throws {}
}

/// A typed notification handler that can be used to handle notifications of a specific type
final class TypedMCPNotificationHandler<N: MCPNotification>: MCPNotificationHandlerBox,
    @unchecked Sendable
{
    private let _handle: @Sendable (MCPMessage<N>) async throws -> Void

    init(_ handler: @escaping @Sendable (MCPMessage<N>) async throws -> Void) {
        self._handle = handler
        super.init()
    }

    override func callAsFunction(_ notification: MCPMessage<AnyMCPNotification>) async throws {
        // Create a concrete notification from the type-erased one
        let data = try JSONEncoder().encode(notification)
        let typedNotification = try JSONDecoder().decode(MCPMessage<N>.self, from: data)

        try await _handle(typedNotification)
    }
}
