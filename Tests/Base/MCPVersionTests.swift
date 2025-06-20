//
//  MCPVersionTests.swift
//  sourced from swift-sdk
//  modified for mcpSwift
//  modify date 18/06/2025
//
//  License MIT
//

import Testing

@testable import MCPSwift

@Suite("Version Negotiation Tests")
struct MCPVersionTests {
    @Test("Client requests latest supported version")
    func testClientRequestsLatestSupportedVersion() {
        let clientVersion = MCPVersion.latest
        let negotiatedVersion = MCPVersion.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == MCPVersion.latest)
    }

    @Test("Client requests older supported version")
    func testClientRequestsOlderSupportedVersion() {
        let clientVersion = "2024-11-05"
        let negotiatedVersion = MCPVersion.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == "2024-11-05")
    }

    @Test("Client requests unsupported version")
    func testClientRequestsUnsupportedVersion() {
        let clientVersion = "2023-01-01"  // An unsupported version
        let negotiatedVersion = MCPVersion.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == MCPVersion.latest)
    }

    @Test("Client requests empty version string")
    func testClientRequestsEmptyVersionString() {
        let clientVersion = ""
        let negotiatedVersion = MCPVersion.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == MCPVersion.latest)
    }

    @Test("Client requests garbage version string")
    func testClientRequestsGarbageVersionString() {
        let clientVersion = "not-a-version"
        let negotiatedVersion = MCPVersion.negotiate(clientRequestedVersion: clientVersion)
        #expect(negotiatedVersion == MCPVersion.latest)
    }

    @Test("Server's supported versions correctly defined")
    func testServerSupportedVersions() {
        #expect(MCPVersion.supported.contains("2025-03-26"))
        #expect(MCPVersion.supported.contains("2024-11-05"))
        #expect(MCPVersion.supported.contains("2025-06-18"))
        #expect(MCPVersion.supported.count == 3)
    }

    @Test("Server's latest version is correct")
    func testServerLatestVersion() {
        #expect(MCPVersion.latest == "2025-06-18")
    }
}
