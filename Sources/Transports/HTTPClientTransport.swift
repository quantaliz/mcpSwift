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
/// The transport supports two modes:
/// - Regular HTTP (`streaming=false`): Simple request/response pattern
/// - Streaming HTTP (`streaming=true`): Enables server-to-client push messages
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
/// let client = MCPClient(name: "MyApp", version: "1.0.0")
/// try await client.connect(transport: transport)
///
/// // The transport will automatically handle SSE events
/// // and deliver them through the client's notification handlers
/// ```
public actor HTTPClientTransport: MCPTransport {
    /// The server endpoint URL to connect to
    public let endpoint: URL
    private let session: URLSession

    /// The session ID assigned by the server, used for maintaining state across requests
    public private(set) var sessionID: String?
    private let streaming: Bool
    private var streamingTask: Task<Void, Never>?

    /// Logger instance for transport-related events
    public nonisolated let logger: Logger

    /// Maximum time to wait for a session ID before proceeding with SSE connection
    public let initTimeout: TimeInterval

    /// Boolean to signal that the HTTPClient can perform requests
    private var transportEnabled = false
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    /// Creates a new HTTP transport client with the specified endpoint
    ///
    /// - Parameters:
    ///   - endpoint: The server URL to connect to
    ///   - configuration: URLSession configuration to use for HTTP requests
    ///   - streaming: Whether to enable SSE streaming mode (default: true)
    ///   - initTimeout: Maximum time to wait for session ID before proceeding with SSE (default: 10 seconds)
    ///   - logger: Optional logger instance for transport events
    public init(
        endpoint: URL,
        configuration: URLSessionConfiguration = .default,
        streaming: Bool = true,
        initTimeout: TimeInterval = 10,
        logger: Logger? = nil
    ) {
        self.endpoint = endpoint
        self.session = URLSession(configuration: configuration)
        self.streaming = streaming
        self.initTimeout = initTimeout

        // Create message stream
        (messageStream, messageContinuation) = AsyncThrowingStream.makeStream(of: Data.self, throwing: Swift.Error.self)
        
        self.logger =
            logger
            ?? Logger(
                label: "mcp.transport.httpclient",
                factory: { _ in SwiftLogNoOpLogHandler() }
            )
    }

    /// Establishes connection with the transport
    ///
    /// This prepares the transport for communication and sets up SSE streaming
    /// if streaming mode is enabled. The actual HTTP connection happens with the
    /// first message sent.
    public func connect() async throws {
        guard !transportEnabled else { return }
        transportEnabled = true

        if streaming {
            // Start listening to server events
            try await startStreaming()
        }

        logger.info("HTTP transport connected")
    }

    /// Disconnects from the transport
    ///
    /// This terminates any active connections, cancels the streaming task,
    /// and releases any resources being used by the transport.
    public func disconnect() async {
        guard transportEnabled else { return }
        transportEnabled = false

        // Cancel streaming task if active
        streamingTask?.cancel()
        streamingTask = nil

        // Cancel any in-progress requests
        session.invalidateAndCancel()

        // Clean up message stream
        messageContinuation.finish()

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
        guard transportEnabled else {
            throw MCPError.internalError("Transport not connected")
        }

        let (responseStream, response) = try await sendRequest(httpMethod: "POST", body: data)
        try await processResponse(response: response, stream: responseStream)
    }
    
    private func sendRequest(httpMethod: String, body: Data?, noCache: Bool = false) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = httpMethod
        request.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if noCache == true {
            request.addValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        
        request.httpBody = body

        // Add session ID if available
        if let sessionID = sessionID {
            request.addValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        
        // macOS and other platforms with bytes(for:) support
        return try await session.bytes(for: request)
    }
    
    /// Process response with byte stream (macOS, iOS, etc.)
    ///
    /// - Parameters:
    ///   - response: The URLResponse object
    ///   - stream: The response data bytes
    /// - Throws: MCPError for data processing failures
    private func processResponse(response: URLResponse,
                                 stream: URLSession.AsyncBytes) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.internalError("Invalid HTTP response")
        }

        // Extract session ID if present
        if let newSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            self.sessionID = newSessionID
            logger.debug("Session ID received", metadata: ["sessionID": "\(newSessionID)"])
        }

        try processHTTPResponse(httpResponse)
        
        guard case 200 ..< 300 = httpResponse.statusCode else {
            throw MCPError.serverError(code: httpResponse.statusCode, message: "Request failed")
        }

        // Process the response based on content type and status code
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") else {
            return
        }
        
        if contentType.contains("text/event-stream") {
            // For SSE, processing happens via the stream
            logger.trace("Received SSE response, processing in streaming task")
            try await self.processSSE(stream)
        } else if contentType.contains("application/json") {
            // For JSON responses, collect and deliver the data
            let buffer = try await processBytes(length: httpResponse.expectedContentLength,
                                                 stream: stream)
            
            logger.trace("Received JSON response", metadata: ["size": "\(buffer.count)"])
            messageContinuation.yield(buffer)
        }
    }
    
    private func processBytes(length: Int64, stream: URLSession.AsyncBytes) async throws -> Data {
        // For JSON responses, collect and deliver the data
        var buffer = Data()
        if length != NSURLSessionTransferSizeUnknown {
            buffer.reserveCapacity(Int(length))
        }
        
        for try await byte in stream {
            buffer.append(byte)
        }
        
        return buffer
    }

    // Common HTTP response handling for all platforms
    private func processHTTPResponse(_ response: HTTPURLResponse) throws {
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
            // If streaming was requested, we should cancel the streaming task
            if streaming {
                self.streamingTask?.cancel()
                throw MCPError.internalError("Server does not support streaming")
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
                "Unexpected HTTP response: \(response.statusCode)")
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
        guard transportEnabled else {
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

    /// Starts listening for server events
    ///
    /// This establishes a long-lived HTTP connection using Server-Sent Events (SSE)
    /// to enable server-to-client push messaging. It handles:
    ///
    /// - Waiting for session ID if needed
    /// - Opening the SSE connection
    /// - Automatic reconnection on connection drops
    /// - Processing received events
    private func startListeningForServerEvents() async {
        // This is the original code for platforms that support SSE
        guard transportEnabled else { return }

        // Retry loop for connection drops
        while transportEnabled && !Task.isCancelled {
            // Wait for the initial session ID signal, but only if sessionID isn't already set
            if self.sessionID == nil {
                let result = await waitForSessionID()
                
                if result == false {
                    logger.error("Session ID not retrieved on time")
                    break
                }
            }
            
            do {
                try await connectToEventStream()
                // If connectToEventStream() returns, the connection was closed normally - break out
                break
            } catch {
                if !Task.isCancelled {
                    logger.error("SSE connection error: \(error)")
                    // Wait before retrying
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }
    
    private func waitForSessionID() async -> Bool {
        try? await Task.sleep(for: .seconds(self.initTimeout))
        if sessionID != nil {
            return true
        }
        else {
            return false
        }
    }
    
    /// Establishes an event connection and processes events
    ///
    /// This follows the MCP specification for Streamable HTTP transport:
    /// 1. Clients MUST use HTTP GET to open an SSE stream
    /// 2. Clients MUST include `Accept: text/event-stream` header
    /// 3. Clients MAY include the session ID if available
    /// 4. Clients MUST support both SSE and HTTP long-polling
    /// This initiates a GET request to the server endpoint with appropriate
    /// headers to establish an SSE stream according to the MCP specification.
    ///
    /// - Throws: MCPError for connection failures or server errors
    private func connectToEventStream() async throws {
        guard transportEnabled else {
            throw MCPError.internalError("Transport not connected")
        }
        
        logger.debug("Starting SSE connection")

        // Create URLSession task for SSE
        let (responseStream, response) = try await sendRequest(httpMethod: "GET", body: nil, noCache: true)
        try await processResponse(response: response, stream: responseStream)
    }

    /// Processes an SSE byte stream, extracting events and delivering them
    ///
    /// - Parameter stream: The URLSession.AsyncBytes stream to process
    /// - Throws: Error for stream processing failures
    private func processSSE(_ stream: URLSession.AsyncBytes) async throws {
        do {
            var activeStream = true
            for try await event in stream.events {
                if !activeStream {
                    break
                }
                
                // Check if task has been cancelled
                if Task.isCancelled { break }

                logger.trace(
                    "SSE event received",
                    metadata: [
                        "type": "\(event.event ?? "message")",
                        "id": "\(event.id ?? "none")",
                    ]
                )
                // Convert the event data to Data and yield it to the message stream
                if !event.data.isEmpty, let data = event.data.data(using: .utf8) {
                    messageContinuation.yield(data)
                }
                
                // Check for server close events
                if event.event == "end" || event.event == "close" {
                    logger.debug("Server explicitly closed SSE stream")
                    activeStream = false
                }
                
            }
        } catch {
            logger.error("Error processing SSE events: \(error)")
            throw error
        }
    }
}
