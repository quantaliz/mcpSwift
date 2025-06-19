//
//  HTTPClientTransport.swift
//  sourced from swift-sdk
//  modified for mcpSwift
//  modify date 18/06/2025
//
//  License MIT
//

import EventSource
import Foundation
import Logging

/// An implementation of the MCP Streamable HTTP transport protocol for clients.
///
/// This transport implements the [Streamable HTTP transport](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#streamable-http)
/// specification from the Model Context Protocol.
///
/// It supports:
/// - Sending JSON-RPC messages via HTTP POST requests
/// - Receiving responses via both direct JSON responses and SSE streams
/// - Session management using the `Mcp-Session-Id` header
/// - Automatic reconnection for dropped SSE streams
/// - Platform-specific optimizations for different operating systems
///
/// - Important: Server-Sent Events (SSE) functionality is not supported on Linux platforms.
///
/// ## Example Usage
///
/// ```swift
/// import MCP
///
/// // Create a streaming HTTP transport
/// let transport = HTTPClientTransport(
///     endpoint: URL(string: "http://localhost:8080")!,
/// )
///
/// // Initialize the client with streaming transport
/// let client = Client(name: "MyApp", version: "1.0.0")
/// try await client.connect(transport: transport)
///
/// // The transport will automatically handle SSE events
/// // and deliver them through the client's notification handlers
/// ```
public actor HTTPClientTransport: Transport {
    /// The server endpoint URL to connect to
    public let endpoint: URL
    private let session: URLSession

    /// The session ID assigned by the server, used for maintaining state across requests
    public private(set) var sessionID: String?
    public let streaming: Bool
    private var streamingTask: Task<Void, Never>?

    /// Logger instance for transport-related events
    public nonisolated let logger: Logger

    /// Maximum time to wait for a session ID before proceeding with SSE connection
    public let sseInitializationTimeout: TimeInterval

    internal var isConnected = false
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    private var initialSessionIDSignalTask: Task<Void, Never>?
    private var initialSessionIDContinuation: CheckedContinuation<Void, Never>?

    /// Creates a new HTTP transport client with the specified endpoint
    ///
    /// - Parameters:
    ///   - endpoint: The server URL to connect to
    ///   - configuration: URLSession configuration to use for HTTP requests
    ///   - streaming: Whether to enable SSE streaming mode (default: true)
    ///   - sseInitializationTimeout: Maximum time to wait for session ID before proceeding with SSE (default: 10 seconds)
    ///   - logger: Optional logger instance for transport events
    public init(
        endpoint: URL,
        configuration: URLSessionConfiguration = .default,
        streaming: Bool = true,
        sseInitializationTimeout: TimeInterval = 10,
        logger: Logger? = nil
    ) {
        self.init(
            endpoint: endpoint,
            session: URLSession(configuration: configuration),
            streaming: streaming,
            sseInitializationTimeout: sseInitializationTimeout,
            logger: logger
        )
    }

    internal init(
        endpoint: URL,
        session: URLSession,
        streaming: Bool = false,
        sseInitializationTimeout: TimeInterval = 10,
        logger: Logger? = nil
    ) {
        self.endpoint = endpoint
        self.session = session
        self.streaming = streaming
        self.sseInitializationTimeout = sseInitializationTimeout

        // Create message stream
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation

        self.logger =
            logger
            ?? Logger(
                label: "mcp.transport.http.client",
                factory: { _ in SwiftLogNoOpLogHandler() }
            )
    }

    // Setup the initial session ID signal
    private func setupInitialSessionIDSignal() {
        self.initialSessionIDSignalTask = Task {
            await withCheckedContinuation { continuation in
                self.initialSessionIDContinuation = continuation
                // This task will suspend here until continuation.resume() is called
            }
        }
    }

    // Trigger the initial session ID signal when a session ID is established
    private func triggerInitialSessionIDSignal() {
        if let continuation = self.initialSessionIDContinuation {
            continuation.resume()
            self.initialSessionIDContinuation = nil  // Consume the continuation
            logger.trace("Initial session ID signal triggered for SSE task.")
        }
    }

    /// Establishes connection with the transport
    ///
    /// This prepares the transport for communication. The actual HTTP connection happens with the
    /// first message sent, and SSE streaming is started via `startStreaming()` if enabled.
    public func connect() async throws {
        guard !isConnected else { return }
        isConnected = true

        // Setup initial session ID signal
        setupInitialSessionIDSignal()

        logger.info("HTTP transport connected")
    }

    /// Disconnects from the transport
    ///
    /// This terminates any active connections, cancels the streaming task,
    /// and releases any resources being used by the transport.
    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false

        // Cancel streaming task if active
        streamingTask?.cancel()
        streamingTask = nil

        // Cancel any in-progress requests
        session.invalidateAndCancel()

        // Clean up message stream
        messageContinuation.finish()

        // Cancel the initial session ID signal task if active
        initialSessionIDSignalTask?.cancel()
        initialSessionIDSignalTask = nil
        // Resume the continuation if it's still pending to avoid leaks
        initialSessionIDContinuation?.resume()
        initialSessionIDContinuation = nil

        logger.info("HTTP clienttransport disconnected")
    }

    /// Sends data through an HTTP POST request
    ///
    /// This sends a JSON-RPC message to the server via HTTP POST and processes
    /// the response according to the MCP Streamable HTTP specification. It handles:
    ///
    /// - Adding appropriate Accept headers for both JSON and SSE
    /// - Including the session ID in requests if one has been established
    /// - Processing different response types (JSON vs SSE)
    /// - Handling HTTP error codes according to the specification
    ///
    /// - Parameter data: The JSON-RPC message to send
    /// - Throws: MCPError for transport failures or server errors
    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw MCPError.internalError("Transport not connected")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        // Add session ID if available
        if let sessionID = sessionID {
            request.addValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }

        #if os(Linux)
            // Linux implementation using data(for:) instead of bytes(for:)
            let (responseData, response) = try await session.data(for: request)
            try await processResponse(response: response, data: responseData)
        #else
            // macOS and other platforms with bytes(for:) support
            let (responseStream, response) = try await session.bytes(for: request)
            try await processResponse(response: response, stream: responseStream)
        #endif
    }
    
    /// Processes an HTTP response from the server
    ///
    /// This handles both JSON and SSE responses according to the MCP specification.
    /// If the response is JSON, it will be delivered directly to the client.
    /// If the response is SSE, it will be processed in a background task.
    ///
    /// - Parameters:
    ///   - response: The HTTPURLResponse object
    ///   - stream: The byte stream containing the response body
    /// - Throws: MCPError for stream processing failures
    private func processResponse(response: URLResponse, stream: URLSession.AsyncBytes) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.internalError("Invalid HTTP response")
        }

        // Process the response based on content type and status code
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        // Extract session ID if present
        if let newSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            let wasSessionIDNil = (self.sessionID == nil)
            self.sessionID = newSessionID
            if wasSessionIDNil {
                // Trigger signal on first session ID
                triggerInitialSessionIDSignal()
            }
            logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
        }

        try processHTTPResponse(httpResponse, contentType: contentType)
        guard case 200..<300 = httpResponse.statusCode else { return }

        if contentType.contains("text/event-stream") {
            // For SSE, processing happens via the stream
            logger.trace("Received SSE response, processing in streaming task")
            try await self.processSSE(stream)
        } else if contentType.contains("application/json") {
            // For JSON responses, collect and deliver the data
            var buffer = Data()
            for try await byte in stream {
                buffer.append(byte)
            }
            logger.trace("Received JSON response", metadata: ["size": "\(buffer.count)"])
            messageContinuation.yield(buffer)
        } else {
            logger.warning("Unexpected content type: \(contentType)")
        }
    }
    
    /// Processes an HTTP response with data payload (Linux)
    ///
    /// - Parameters:
    ///   - response: The HTTPURLResponse object
    ///   - data: The response data
    /// - Throws: MCPError for data processing failures
    private func processResponse(response: HTTPURLResponse, data: Data) async throws {
        // Process response headers
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""

        // Extract session ID if present
        if let newSessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
            let wasSessionIDNil = (self.sessionID == nil)
            self.sessionID = newSessionID
            if wasSessionIDNil {
                // Trigger signal on first session ID
                triggerInitialSessionIDSignal()
            }
            logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
        }

        try processHTTPResponse(response, contentType: contentType)
        guard case 200..<300 = response.statusCode else { return }

        // For JSON responses, deliver the data directly
        if contentType.contains("application/json") {
            logger.trace("Received JSON response", metadata: ["size": "\(data.count)"])
            messageContinuation.yield(data)
        } else {
            logger.warning("Unexpected content type: \(contentType)")
        }
    }

    #if os(Linux)
        // Process response with data payload (Linux)
        private func processResponse(response: URLResponse, data: Data) async throws {
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPError.internalError("Invalid HTTP response")
            }

            // Process the response based on content type and status code
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

            // Extract session ID if present
            if let newSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
                let wasSessionIDNil = (self.sessionID == nil)
                self.sessionID = newSessionID
                if wasSessionIDNil {
                    // Trigger signal on first session ID
                    triggerInitialSessionIDSignal()
                }
                logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
            }

            try processHTTPResponse(httpResponse, contentType: contentType)
            guard case 200..<300 = httpResponse.statusCode else { return }

            // For JSON responses, yield the data
            if contentType.contains("text/event-stream") {
                logger.warning("SSE responses aren't fully supported on Linux")
                messageContinuation.yield(data)
            } else if contentType.contains("application/json") {
                logger.trace("Received JSON response", metadata: ["size": "\(data.count)"])
                messageContinuation.yield(data)
            } else {
                logger.warning("Unexpected content type: \(contentType)")
            }
        }
    #else
        // Process response with byte stream (macOS, iOS, etc.)
        private func processResponse(response: URLResponse, stream: URLSession.AsyncBytes)
            async throws {
            guard let httpResponse = response as? HTTPURLResponse else { // Corrected line
                throw MCPError.internalError("Invalid HTTP response")
            }

            // Process the response based on content type and status code
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

            // Extract session ID if present
            if let newSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
                let wasSessionIDNil = (self.sessionID == nil)
                self.sessionID = newSessionID
                if wasSessionIDNil {
                    // Trigger signal on first session ID
                    triggerInitialSessionIDSignal()
                }
                logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
            }

            try processHTTPResponse(httpResponse, contentType: contentType)
            guard case 200..<300 = httpResponse.statusCode else { return }

            if contentType.contains("text/event-stream") {
                // For SSE, processing happens via the stream
                logger.trace("Received SSE response, processing in streaming task")
                try await self.processSSE(stream)
            } else if contentType.contains("application/json") {
                // For JSON responses, collect and deliver the data
                var buffer = Data()
                for try await byte in stream {
                    buffer.append(byte)
                }
                logger.trace("Received JSON response", metadata: ["size": "\(buffer.count)"])
                messageContinuation.yield(buffer)
            } else {
                logger.warning("Unexpected content type: \(contentType)")
            }
        }
    #endif

    // Common HTTP response handling for all platforms
    private func processHTTPResponse(_ response: HTTPURLResponse, contentType: String) throws {
        // Handle status codes according to HTTP semantics
        switch response.statusCode {
        case 200..<300:
            // Success range - these are handled by the platform-specific code
            return

        case 400:
            throw MCPError.internalError("Bad request")

        case 401:
            throw MCPError.internalError("Authentication required")

        case 403:
            throw MCPError.internalError("Access forbidden")

        case 404:
            // If we get a 404 with a session ID, it means our session is invalid
            if sessionID != nil {
                logger.warning("Session has expired")
                sessionID = nil
                throw MCPError.internalError("Session expired")
            }
            throw MCPError.internalError("Endpoint not found")

        case 405:
            // If we get a 405, it means the server does not support the requested method
            // According to MCP spec, servers MAY respond with 405 Method Not Allowed
            // if they don't support SSE streaming
            if streaming {
                logger.info("Server does not support SSE streaming")
                // Don't cancel the streaming task - we'll use HTTP long polling
                return
            }
            throw MCPError.internalError("Method not allowed")

        case 408:
            throw MCPError.internalError("Request timeout")

        case 429:
            throw MCPError.internalError("Too many requests")

        case 500..<600:
            // Server error range
            throw MCPError.internalError("Server error: \(response.statusCode)")

        default:
            throw MCPError.internalError(
                "Unexpected HTTP response: \(response.statusCode) (\(contentType))")
        }
    }

    /// Receives data in an async sequence
    ///
    /// This returns an AsyncThrowingStream that emits Data objects representing
    /// each JSON-RPC message received from the server. This includes:
    ///
    /// - Direct responses to client requests
    /// - Server-initiated messages delivered via SSE streams
    ///
    /// - Returns: An AsyncThrowingStream of Data objects
    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }

    /// Starts listening for server events using SSE.
    ///
    /// This method should be called by the client after successful initialization
    /// and capability negotiation, if streaming is desired and supported.
    ///
    /// - Throws: `MCPError.internalError` if the transport is not connected or streaming is disabled.
    public func startStreaming() async throws {
        guard streaming else {
            logger.info("Streaming is disabled for this transport instance.")
            return
        }
        guard isConnected else {
            throw MCPError.internalError("Transport not connected, cannot start streaming.")
        }
        guard streamingTask == nil else {
            logger.info("Streaming task already running.")
            return
        }

        // Start listening to server events
        streamingTask = Task { await startListeningForServerEvents() }
        logger.info("HTTP transport streaming started.")
    }

    // MARK: - SSE

    /// Starts listening for server events using SSE
    ///
    /// Sends a GET request to establish an SSE connection or long-polling
    ///
    /// This follows the MCP specification for Streamable HTTP transport:
    /// 1. Clients MUST include the `Accept: text/event-stream` header
    /// 2. Clients MUST use the same endpoint URL as for POST requests
    /// 3. Clients SHOULD include the session ID if available
    ///
    /// - Returns: A tuple containing the byte stream and HTTP response
    /// - Throws: MCPError for connection failures
    private func establishEventConnection() async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        // Add session ID if available
        if let sessionID = sessionID {
            request.addValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        
        logger.debug("Establishing event connection", metadata: [
            "url": endpoint.absoluteString,
            "sessionID": sessionID ?? "none"
        ])
        
        #if os(Linux)
        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.internalError("Invalid HTTP response")
        }
        return (responseData.makeAsyncBytes(), httpResponse)
        #else
        let (stream, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.internalError("Invalid HTTP response")
        }
        return (stream, httpResponse)
        #endif
    }

    /// Starts listening for server events using SSE
    ///
    /// This establishes a long-lived HTTP connection using Server-Sent Events (SSE)
    /// to enable server-to-client push messaging. It handles:
    ///
    /// - Waiting for session ID if needed
    /// - Opening the SSE connection
    /// - Automatic reconnection on connection drops
    /// - Processing received events
    private func startListeningForServerEvents() async {
        #if os(Linux)
            // SSE is not fully supported on Linux
            if streaming {
                logger.warning(
                    "SSE streaming was requested but is not fully supported on Linux. SSE connection will not be attempted."
                )
            }
        #else
            // This is the original code for platforms that support SSE
            guard isConnected else { return }

            // Retry loop for connection drops
            while isConnected && !Task.isCancelled {
                do {
                    try await connectToEventStream()
                } catch {
                    if !Task.isCancelled {
                        logger.error("SSE connection error: \(error)")
                        // Wait before retrying
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
            }
        #endif
    }
    
    /// Establishes an event connection and processes events
    ///
    /// This follows the MCP specification for Streamable HTTP transport:
    /// 1. Clients MUST use HTTP GET to open an SSE stream
    /// 2. Clients MUST include `Accept: text/event-stream` header
    /// 3. Clients MAY include the session ID if available
    /// 4. Clients MUST support both SSE and HTTP long-polling
    ///
    /// - Throws: MCPError for connection failures
    private func connectToEventStream() async throws {
        guard isConnected else { return }
        
        // Establish connection and get response
        let (stream, httpResponse) = try await establishEventConnection()
        
        // Check response status
        guard httpResponse.statusCode == 200 else {
            // According to MCP spec, servers MAY respond with 405 Method Not Allowed
            // if they don't support SSE streaming. In that case, we should continue
            // trying to connect periodically.
            if httpResponse.statusCode == 405 {
                logger.info("Server does not support SSE streaming - continuing with long-polling")
                // Wait before retrying connection
                try? await Task.sleep(for: .seconds(1))
                return
            }
            throw MCPError.internalError("HTTP error: \(httpResponse.statusCode)")
        }
        
        // Extract session ID if present
        if let newSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            let wasSessionIDNil = (self.sessionID == nil)
            self.sessionID = newSessionID
            if wasSessionIDNil {
                // Trigger signal on first session ID
                triggerInitialSessionIDSignal()
            }
            logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
        }
        
        // Process the stream according to content type
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            // Handle SSE stream
            try await processSSE(stream)
        } else if contentType.contains("application/json") {
            // Handle HTTP long-polling response
            var buffer = Data()
            #if os(Linux)
            // For Linux, we can directly process the data
            if case let .data(data) = stream {
                buffer = data
            }
            #else
            // For other platforms, collect bytes from the stream
            for try await byte in stream {
                buffer.append(byte)
            }
            #endif
            if !buffer.isEmpty {
                messageContinuation.yield(buffer)
            }
        } else {
            logger.warning("Unsupported content type: $contentType)")
        }
    }

    /// Processes an SSE byte stream, extracting events and delivering them
    ///
    /// - Parameter stream: The URLSession.AsyncBytes stream to process
    /// - Throws: Error for stream processing failures
    private func processSSE(_ stream: URLSession.AsyncBytes) async throws {
        for try await event in stream.events {
            // Check if task has been cancelled
            if Task.isCancelled { break }

            logger.trace(
                "SSE event received",
                metadata: [
                    "type": "\(event.event ?? "message")",
                    "id": "\(event.id ?? "none")"
                ]
            )
            
            // Handle event data
            if !event.data.isEmpty {
                // According to MCP spec, each event data field contains a single JSON-RPC message
                if let data = event.data.data(using: .utf8) {
                    messageContinuation.yield(data)
                }
            }
        }
        
        logger.debug("SSE stream ended - will reconnect")
    }
}
