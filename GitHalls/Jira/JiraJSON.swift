//
//  JiraJSON.swift
//  GitHalls
//

import Foundation

/// JSON a value can hold, as a Sendable enum. Custom fields are whatever shape
/// the Jira admin chose, so edits carry them as data rather than as `Any`.
enum JiraJSON: Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JiraJSON])
    case object([String: JiraJSON])

    /// What `JSONSerialization` writes.
    var foundation: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        case .array(let values): values.map(\.foundation)
        case .object(let values): values.mapValues(\.foundation)
        }
    }

    /// Reads the output of `JSONSerialization`; nil for anything else.
    init?(foundation: Any) {
        switch foundation {
        case let value as String: self = .string(value)
        case is NSNull: self = .null
        case let value as NSNumber:
            // Booleans arrive as NSNumber too; the CF type tells them apart.
            self = CFGetTypeID(value) == CFBooleanGetTypeID() ? .bool(value.boolValue) : .number(value.doubleValue)
        case let values as [Any]: self = .array(values.compactMap(JiraJSON.init(foundation:)))
        case let values as [String: Any]: self = .object(values.compactMapValues(JiraJSON.init(foundation:)))
        default: return nil
        }
    }
}
