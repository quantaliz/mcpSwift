//
//  MCPIDTests.swift
//  sourced from swift-sdk
//  modified for mcpSwift
//  modify date 18/06/2025
//
//  License MIT
//

import Testing

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.UUID

@testable import MCPSwift

@Suite("MCPID Tests")
struct MCPIDTests {
    @Test("String MCPID initialization and encoding")
    func testStringMCPID() throws {
        let id: MCPID = "test-id"
        #expect(id.description == "test-id")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(id)
        let decoded = try decoder.decode(MCPID.self, from: data)
        #expect(decoded == id)
    }

    @Test("Number MCPID initialization and encoding")
    func testNumberMCPID() throws {
        let id: MCPID = 42
        #expect(id.description == "42")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(id)
        let decoded = try decoder.decode(MCPID.self, from: data)
        #expect(decoded == id)
    }

    @Test("Random MCPID generation")
    func testRandomMCPID() throws {
        let id1 = MCPID.random
        let id2 = MCPID.random
        #expect(id1 != id2, "Random MCPIDs should be unique")

        if case .string(let str) = id1 {
            #expect(!str.isEmpty)
            // Verify it's a valid UUMCPID string
            #expect(UUID(uuidString: str) != nil)
        } else {
            #expect(Bool(false), "Random MCPID should be string type")
        }
    }
}
