//
//  HTTPSSETransport.swift
//  sourced from swift-sdk
//  modified for mcpSwift
//  modify date 18/06/2025
//
//  License MIT
//

import EventSource
import Foundation
import Logging

/// An implementation of the MCP HTTP+SSE transport protocol for clients.
///
/// This transport implements the [HTTP with SSE transport](https://modelcontextprotocol.io/specification/2024-11-05/basic/transports#http-with-sse)
/// specification from the Model Context Protocol.
///
/// It supports:
/// - Sending JSON-RPC messages via HTTP POST requests
/// - Receiving responses via SSE stream
/// - Session management using the `session_id`
/// - Automatic reconnection for dropped SSE streams
///
/// ## Example Usage
///
/// ```swift
/// import MCP
///
/// // Create a streaming HTTP transport
/// let transport = HTTPSSETransport(
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
public actor HTTPSSETransport {
    /// The server endpoint URL to connect to
    public var endpoint: URL
    private let session: URLSession
    
    /// The session ID assigned by the server, used for maintaining state across requests
    public private(set) var sessionID: String?
    private var streamingTask: Task<Void, Never>?
    
    /// Logger instance for transport-related events
    public nonisolated let logger: Logger
    
    /// Maximum time to wait for a session ID before proceeding with SSE connection
    public let initTimeout: Duration
    
    /// SSE needs to return the endpoint to use for POST requests
    private var waitingEndpoint: Bool = true
    
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
        initTimeout: Duration = .seconds(5),
        logger: Logger? = nil
    ) {
        self.endpoint = endpoint
        self.session = URLSession(configuration: configuration)
        
        self.initTimeout = initTimeout
        
        // Create message stream
        (messageStream, messageContinuation) = AsyncThrowingStream.makeStream(of: Data.self, throwing: Swift.Error.self)
        
        self.logger = logger
        ?? Logger(
            label: "mcp.transport.httpsse",
            factory: { _ in SwiftLogNoOpLogHandler() }
        )
    }
}

// MARK: - MCPTransport protocol functions

extension HTTPSSETransport: MCPTransport  {
        
    /// Establishes connection with the transport
    ///
    /// This prepares the transport for communication and sets up SSE streaming
    /// if streaming mode is enabled. The actual HTTP connection happens with the
    /// first message sent.
    public func connect() async throws {
        guard !transportEnabled else { return }
        transportEnabled = true
        
        try await connectToEventStream()
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
        
        logger.info("HTTP+SSE transport disconnected")
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
        
        while waitingEndpoint == true {
            try await Task.sleep(for: initTimeout)
            if waitingEndpoint == true {
                throw MCPError.requestTimeout
            }
        }
        
        let (responseStream, response) = try await sendRequest(httpMethod: "POST", body: data)
        try await processResponse(response: response, stream: responseStream)
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
    
}

// MARK: - Extra functions

extension HTTPSSETransport {
    
    private func sendRequest(httpMethod: String, body: Data?, noCache: Bool = false) async throws -> (URLSession.AsyncBytes, URLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = httpMethod
        request.addValue("application/json", forHTTPHeaderField: "Accept")
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
        
        try HTTPTransportShared.processHTTPResponse(httpResponse)
        
        // Process the response based on content type and status code
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") else {
            #if DEBUG
            logger.warning("No known content type for response")
            let buffer = try await HTTPTransportShared.processBytes(length: httpResponse.expectedContentLength,
                                                                    stream: stream)
            let str = String(data: buffer, encoding: .utf8) ?? "[binary data]"
            logger.trace("Response bytes: `\(str)`", metadata: ["size": "\(buffer.count)"])
            #endif
            return
        }
        
        if contentType.contains("text/event-stream") {
            // For SSE, processing happens via the stream
            logger.trace("Received SSE response, processing in streaming task")
            try await processSSE(stream)
        } else if contentType.contains("application/json") {
            // For JSON responses, collect and deliver the data
            let buffer = try await HTTPTransportShared.processBytes(length: httpResponse.expectedContentLength,
                                                                    stream: stream)
            
            logger.trace("Received JSON response", metadata: ["size": "\(buffer.count)"])
            messageContinuation.yield(buffer)
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
        
        waitingEndpoint = true
        // Create URLSession task for SSE
        streamingTask = Task {
            logger.trace("Starting SSE connection")
            do {
                let (responseStream, response) = try await sendRequest(httpMethod: "GET", body: nil, noCache: true)
                try await processResponse(response: response, stream: responseStream)
            }
            catch {
                logger.error("SSE connection failed: \(error)")
                return
            }
            logger.trace("SSE connection finished")
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
            
            processEvent(event)
            
            // Check for server close events
            if event.event == "end" || event.event == "close" {
                logger.trace("Server explicitly closed SSE stream")
                break
            }
        }
    }
    
    func processEvent(_ event: EventSource.Event) {
        logger.trace(
            "SSE event received",
            metadata: [
                "type": "\(event.event ?? "message")",
                "id": "\(event.id ?? "none")",
            ]
        )
        
        // Convert the event data to Data and yield it to the message stream
        guard !event.data.isEmpty, let data = event.data.data(using: .utf8) else {
            logger.warning("Empty data from SSE")
            return
        }
        
        if event.event == "endpoint" {
            endpoint = HTTPTransportShared.retrieveURL(data, endpoint: endpoint)
            waitingEndpoint = false
        }
        else {
            messageContinuation.yield(data)
        }
    }
}
