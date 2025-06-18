# Quantaliz' mcpSwift
MCP developed in Swift for clients. This is a "hard" fork from the [original repository](https://github.com/modelcontextprotocol/swift-sdk)

## Overview

The Model Context Protocol (MCP) defines a standardized way for applications to communicate with AI and ML models.
This `mcpSwift` implements only the client components according to the [2025-03-26][mcp-spec-2025-03-26] version of the MCP specification.

Check the [original repository](https://github.com/modelcontextprotocol/swift-sdk) for server support.

## Requirements

- Swift 6.1+ (Xcode 16+)

See the [Platform Availability](#platform-availability) section below for platform-specific requirements.

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/quantaliz/mcpSwift.git", from: "0.9.0")
]
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MCPSwift", package: "mcpSwift")
    ]
)
```

## Client usage

Check the Examples folder for further details

## Platform Availability

The Quantaliz' mcpSwift  has the following platform requirements:

| Platform | Minimum Version |
|----------|-----------------|
| macOS    | 14.0+ |
| iOS / Mac Catalyst | 17.0+ |
| watchOS  | 10.0+ |
| tvOS     | 17.0+ |
| visionOS | 2.0+ |

If you need backwards compatibility check the original repostory: [MCP swift-sdk](https://github.com/modelcontextprotocol/swift-sdk)

An alternative MCP library with server support is [SwiftMCP](https://github.com/Cocoanetics/SwiftMCP/).

## Additional Resources

- [MCP Specification](https://modelcontextprotocol.io/specification/2025-03-26/)
- [GitHub Repository](https://github.com/quantaliz/mcpSwift)

## License

This project is licensed under the MIT License.

[mcp]: https://modelcontextprotocol.io
[mcp-spec-2025-03-26]: https://modelcontextprotocol.io/specification/2025-03-26