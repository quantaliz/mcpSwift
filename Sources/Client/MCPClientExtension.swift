//
//  MCPClient.swift
//  sourced from swift-sdk
//  modified for mcpSwift
//  modify date 18/06/2025
//
//  License MIT
//

import Logging

import struct Foundation.Data
import struct Foundation.Date
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// Model Context Protocol client
public extension MCPClient {
    /// The client configuration
    struct Configuration: Hashable, Codable, Sendable {
        /// The default configuration.
        public static let `default` = Configuration(strict: false)

        /// The strict configuration.
        public static let strict = Configuration(strict: true)

        /// When strict mode is enabled, the client:
        /// - Requires server capabilities to be initialized before making requests
        /// - Rejects all requests that require capabilities before initialization
        ///
        /// While the MCP specification requires servers to respond to initialize requests
        /// with their capabilities, some implementations may not follow this.
        /// Disabling strict mode allows the client to be more lenient with non-compliant
        /// servers, though this may lead to undefined behavior.
        public var strict: Bool

        public init(strict: Bool = false) {
            self.strict = strict
        }
    }

    /// Implementation information
    struct Info: Hashable, Codable, Sendable {
        /// The client name
        public var name: String
        /// The client version
        public var version: String

        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    /// The client capabilities
    struct Capabilities: Hashable, Codable, Sendable {
        /// The roots capabilities
        public struct Roots: Hashable, Codable, Sendable {
            /// Whether the list of roots has changed
            public var listChanged: Bool?

            public init(listChanged: Bool? = nil) {
                self.listChanged = listChanged
            }
        }

        /// The sampling capabilities
        public struct Sampling: Hashable, Codable, Sendable {
            public init() {}
        }

        /// Whether the client supports sampling
        public var sampling: Sampling?
        /// Experimental features supported by the client
        public var experimental: [String: String]?
        /// Whether the client supports roots
        public var roots: Capabilities.Roots?

        public init(
            sampling: Sampling? = nil,
            experimental: [String: String]? = nil,
            roots: Capabilities.Roots? = nil
        ) {
            self.sampling = sampling
            self.experimental = experimental
            self.roots = roots
        }
    }

    /// An error indicating a type mismatch when decoding a pending request
    struct TypeMismatchError: Swift.Error {}

    /// A pending request with a continuation for the result
    struct PendingRequest<T> {
        let continuation: CheckedContinuation<T, Swift.Error>
    }

    /// A type-erased pending request
    struct AnyPendingRequest {
        private let _resume: (Result<Any, Swift.Error>) -> Void

        init<T: Sendable & Decodable>(_ request: PendingRequest<T>) {
            _resume = { result in
                switch result {
                case .success(let value):
                    if let typedValue = value as? T {
                        request.continuation.resume(returning: typedValue)
                    } else if let value = value as? MCPValue,
                        let data = try? JSONEncoder().encode(value),
                        let decoded = try? JSONDecoder().decode(T.self, from: data)
                    {
                        request.continuation.resume(returning: decoded)
                    } else {
                        request.continuation.resume(throwing: TypeMismatchError())
                    }
                case .failure(let error):
                    request.continuation.resume(throwing: error)
                }
            }
        }
        func resume(returning value: Any) {
            _resume(.success(value))
        }

        func resume(throwing error: Swift.Error) {
            _resume(.failure(error))
        }
    }

    // MARK: - Batching

    /// A batch of requests.
    ///
    /// Objects of this type are passed as an argument to the closure
    /// of the ``MCPClient/withBatch(_:)`` method.
    actor Batch {
        unowned let client: MCPClient
        var requests: [AnyMCPRequest] = []

        init(client: MCPClient) {
            self.client = client
        }

        /// Adds a request to the batch and prepares its expected response task.
        /// The actual sending happens when the `withBatch` scope completes.
        /// - Returns: A `Task` that will eventually produce the result or throw an error.
        public func addRequest<M: MCPMethod>(_ request: MCPRequest<M>) async throws -> Task<
            M.Result, Swift.Error
        > {
            requests.append(try AnyMCPRequest(request))

            // Return a Task that registers the pending request and awaits its result.
            // The continuation is resumed when the response arrives.
            return Task<M.Result, Swift.Error> {
                try await withCheckedThrowingContinuation { continuation in
                    // We are already inside a Task, but need another Task
                    // to bridge to the client actor's context.
                    Task {
                        await client.addPendingRequest(
                            id: request.id,
                            continuation: continuation,
                            type: M.Result.self
                        )
                    }
                }
            }
        }
    }
}
