//
//  HTTPTransportShared.swift
//  mcpSwift
//
//  Created on 4/7/2025.
//

import Foundation.NSURLResponse

enum HTTPTransportShared
{
    static func retrieveURL(_ data: Data, endpoint: URL) -> URL {
        guard let extra = String(data: data, encoding: .utf8),
              var endpointComp = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)
        else {
            return endpoint
        }
        
        endpointComp.path = extra
        if let finalEndpoint = endpointComp.url?.absoluteString.removingPercentEncoding,
           let finalURL = URL(string: finalEndpoint)
        {
            return finalURL
        }
        else {
            return endpoint
        }
    }
    
    static func processBytes(length: Int64, stream: URLSession.AsyncBytes) async throws -> Data {
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
    /// Processes HTTP responses according to MCP specification
    ///
    /// - Parameter response: HTTPURLResponse to validate
    /// - Throws: `MCPError` for non-2xx status codes
    static func processHTTPResponse(_ response: HTTPURLResponse) throws {
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
//            if sessionID != nil {
//                logger.warning("Session has expired")
//                sessionID = nil
//                throw MCPError.internalError("Session expired")
//            }
            throw MCPError.internalError("Endpoint not found")

        case 405:
            // If we get a 405, it means the server does not support the requested method
            // If streaming was requested, we should cancel the streaming task
//            if streaming {
//                self.streamingTask?.cancel()
//            }
            throw MCPError.methodNotAllowed

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
}
