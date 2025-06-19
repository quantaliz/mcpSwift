//
//  ClientTests.swift
//  sourced from swift-sdk
//  modified for mcpSwift
//  modify date 18/06/2025
//
//  License MIT
//

import Foundation
import Logging
import Testing

@testable import MCPSwift

@Suite("ClientExternal Tests")
struct ClientExternalTests {
    @Test(
        "Connect to live server and list capabilities",
        .timeLimit(.minutes(1))  // Set a 1-minute timeout for the entire test
    )
    func testLiveServerConnectionAndCapabilities() async throws {
        let logger = Logger(label: "com.mcpswift")
        let url = URL(
            string:
                "https://agents-mcp-hackathon-quantaliz-mcp-micropayments.hf.space/gradio_api/mcp/sse"
        )!
        let transport = HTTPClientTransport(endpoint: url, streaming: true, logger: logger)
        let client = Client(name: "TestClient", version: "1.0")

        // Connect to the server
        _ = try await client.connect(transport: transport)
        #expect(await transport.isConnected == true, "Client should be connected")

        // List prompts
        let (prompts, _) = try await client.listPrompts()
        // Prompts can be empty, so no specific check on count, just that the call succeeded
        print("Found \(prompts.count) prompts.")

        // List resources
        let (resources, _) = try await client.listResources()
        // Resources can be empty
        print("Found \(resources.count) resources.")

        // List tools
        let (tools, _) = try await client.listTools()
        #expect(!tools.isEmpty, "List of tools should not be empty")
        print("Found \(tools.count) tools.")

        // Disconnect
        await client.disconnect()
        #expect(await transport.isConnected == false, "Client should be disconnected")
    }
}
