//
//  Foundation+Extensions.swift
//  mcpSwift
//
//  Created on 20/6/2025.
//  License MIT
//

// MARK: - Standard Library Type Extensions

extension Bool {
    /// Creates a boolean value from a `Value` instance.
    ///
    /// In strict mode, only `.bool` values are converted. In non-strict mode, the following conversions are supported:
    /// - Integers: `1` is `true`, `0` is `false`
    /// - Doubles: `1.0` is `true`, `0.0` is `false`
    /// - Strings (lowercase only):
    ///   - `true`: "true", "t", "yes", "y", "on", "1"
    ///   - `false`: "false", "f", "no", "n", "off", "0"
    ///
    /// - Parameters:
    ///   - value: The `Value` to convert
    ///   - strict: When `true`, only converts from `.bool` values. Defaults to `true`
    /// - Returns: A boolean value if conversion is possible, `nil` otherwise
    ///
    /// - Example:
    ///   ```swift
    ///   Bool(Value.bool(true)) // Returns true
    ///   Bool(Value.int(1), strict: false) // Returns true
    ///   Bool(Value.string("yes"), strict: false) // Returns true
    ///   ```
    public init?(_ value: MCPValue, strict: Bool = true) {
        switch value {
        case .bool(let b):
            self = b
        case .int(let i) where !strict:
            switch i {
            case 0: self = false
            case 1: self = true
            default: return nil
            }
        case .double(let d) where !strict:
            switch d {
            case 0.0: self = false
            case 1.0: self = true
            default: return nil
            }
        case .string(let s) where !strict:
            switch s {
            case "true", "t", "yes", "y", "on", "1":
                self = true
            case "false", "f", "no", "n", "off", "0":
                self = false
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

extension Int {
    /// Creates an integer value from a `Value` instance.
    ///
    /// In strict mode, only `.int` values are converted. In non-strict mode, the following conversions are supported:
    /// - Doubles: Converted if they can be represented exactly as integers
    /// - Strings: Parsed if they contain a valid integer representation
    ///
    /// - Parameters:
    ///   - value: The `Value` to convert
    ///   - strict: When `true`, only converts from `.int` values. Defaults to `true`
    /// - Returns: An integer value if conversion is possible, `nil` otherwise
    ///
    /// - Example:
    ///   ```swift
    ///   Int(Value.int(42)) // Returns 42
    ///   Int(Value.double(42.0), strict: false) // Returns 42
    ///   Int(Value.string("42"), strict: false) // Returns 42
    ///   Int(Value.double(42.5), strict: false) // Returns nil
    ///   ```
    public init?(_ value: MCPValue, strict: Bool = true) {
        switch value {
        case .int(let i):
            self = i
        case .double(let d) where !strict:
            guard let intValue = Int(exactly: d) else { return nil }
            self = intValue
        case .string(let s) where !strict:
            guard let intValue = Int(s) else { return nil }
            self = intValue
        default:
            return nil
        }
    }
}

extension Double {
    /// Creates a double value from a `Value` instance.
    ///
    /// In strict mode, converts from `.double` and `.int` values. In non-strict mode, the following conversions are supported:
    /// - Integers: Converted to their double representation
    /// - Strings: Parsed if they contain a valid floating-point representation
    ///
    /// - Parameters:
    ///   - value: The `Value` to convert
    ///   - strict: When `true`, only converts from `.double` and `.int` values. Defaults to `true`
    /// - Returns: A double value if conversion is possible, `nil` otherwise
    ///
    /// - Example:
    ///   ```swift
    ///   Double(Value.double(42.5)) // Returns 42.5
    ///   Double(Value.int(42)) // Returns 42.0
    ///   Double(Value.string("42.5"), strict: false) // Returns 42.5
    ///   ```
    public init?(_ value: MCPValue, strict: Bool = true) {
        switch value {
        case .double(let d):
            self = d
        case .int(let i):
            self = Double(i)
        case .string(let s) where !strict:
            guard let doubleValue = Double(s) else { return nil }
            self = doubleValue
        default:
            return nil
        }
    }
}

extension String {
    /// Creates a string value from a `Value` instance.
    ///
    /// In strict mode, only `.string` values are converted. In non-strict mode, the following conversions are supported:
    /// - Integers: Converted to their string representation
    /// - Doubles: Converted to their string representation
    /// - Booleans: Converted to "true" or "false"
    ///
    /// - Parameters:
    ///   - value: The `Value` to convert
    ///   - strict: When `true`, only converts from `.string` values. Defaults to `true`
    /// - Returns: A string value if conversion is possible, `nil` otherwise
    ///
    /// - Example:
    ///   ```swift
    ///   String(Value.string("hello")) // Returns "hello"
    ///   String(Value.int(42), strict: false) // Returns "42"
    ///   String(Value.bool(true), strict: false) // Returns "true"
    ///   ```
    public init?(_ value: MCPValue, strict: Bool = true) {
        switch value {
        case .string(let s):
            self = s
        case .int(let i) where !strict:
            self = String(i)
        case .double(let d) where !strict:
            self = String(d)
        case .bool(let b) where !strict:
            self = String(b)
        default:
            return nil
        }
    }
}
