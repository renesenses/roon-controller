import Foundation

// MARK: - MOO Protocol Message

/// Represents a MOO/1 protocol message used by Roon Core.
/// Format: `MOO/1 {VERB} {name}\nHeader: value\n...\n\n{body}`
struct MOOMessage {

    enum Verb: String {
        case request = "REQUEST"
        case complete = "COMPLETE"
        case `continue` = "CONTINUE"
    }

    let verb: Verb
    let name: String
    let requestId: Int
    let headers: [String: String]
    let body: Data?

    // MARK: - Convenience accessors

    var isSuccess: Bool {
        headers["Roon-Status"]?.lowercased() == "success" || headers["Roon-Status"] == nil
    }

    var contentType: String? {
        headers["Content-Type"]
    }

    var isJSON: Bool {
        guard let ct = contentType else { return body != nil }
        return ct.contains("application/json")
    }

    /// Decode body as JSON
    func decodeBody<T: Decodable>(_ type: T.Type) -> T? {
        guard let body = body else { return nil }
        return try? JSONDecoder().decode(type, from: body)
    }

    /// Body as JSON dictionary
    var bodyJSON: [String: Any]? {
        guard let body = body else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    // MARK: - Parsing

    /// Parse a MOO message from raw WebSocket binary data.
    static func parse(_ data: Data) -> MOOMessage? {
        // Find the header/body separator: \n\n
        guard let separatorRange = findHeaderSeparator(in: data) else { return nil }

        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let bodyStart = separatorRange.upperBound
        let body: Data? = bodyStart < data.endIndex ? data[bodyStart..<data.endIndex] : nil

        // Parse first line: "MOO/1 VERB name"
        let lines = headerString.components(separatedBy: "\n")
        guard let firstLine = lines.first else { return nil }

        let parts = firstLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 3,
              parts[0] == "MOO/1",
              let verb = Verb(rawValue: String(parts[1])) else { return nil }

        let name = String(parts[2])

        // Parse headers
        var headers: [String: String] = [:]
        var requestId: Int?

        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { continue }
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            if key == "Request-Id" {
                requestId = Int(value)
            } else {
                headers[key] = value
            }
        }

        guard let rid = requestId else { return nil }

        return MOOMessage(verb: verb, name: name, requestId: rid, headers: headers, body: body)
    }

    // MARK: - Building

    /// Build a MOO REQUEST message.
    static func request(name: String, requestId: Int, body: Data? = nil) -> Data {
        build(verb: .request, name: name, requestId: requestId, body: body)
    }

    /// Build a MOO REQUEST message with a JSON dictionary body.
    static func request(name: String, requestId: Int, jsonBody: [String: Any]) -> Data {
        let jsonData = try? JSONSerialization.data(withJSONObject: jsonBody)
        return build(verb: .request, name: name, requestId: requestId, body: jsonData)
    }

    /// Build a MOO COMPLETE response (for responding to Core requests like ping).
    static func complete(name: String, requestId: Int, body: Data? = nil) -> Data {
        build(verb: .complete, name: name, requestId: requestId, body: body)
    }

    /// Build a MOO CONTINUE response.
    static func continueMessage(name: String, requestId: Int, body: Data? = nil) -> Data {
        build(verb: .continue, name: name, requestId: requestId, body: body)
    }

    // MARK: - Internal

    private static func build(verb: Verb, name: String, requestId: Int, body: Data?) -> Data {
        var header = "MOO/1 \(verb.rawValue) \(name)\nRequest-Id: \(requestId)"

        if let body = body, !body.isEmpty {
            header += "\nContent-Type: application/json"
            header += "\nContent-Length: \(body.count)"
        }

        header += "\n\n"

        var result = Data(header.utf8)
        if let body = body {
            result.append(body)
        }
        return result
    }

    /// Find the \n\n separator between headers and body.
    private static func findHeaderSeparator(in data: Data) -> Range<Data.Index>? {
        let newline = UInt8(ascii: "\n")
        var i = data.startIndex
        while i < data.endIndex {
            if data[i] == newline {
                let next = data.index(after: i)
                if next < data.endIndex && data[next] == newline {
                    return i..<data.index(after: next)
                }
            }
            i = data.index(after: i)
        }
        return nil
    }
}

// MARK: - Request ID Generator

/// Thread-safe atomic request ID generator for MOO protocol.
final class MOORequestIdGenerator: @unchecked Sendable {
    private var _nextId: Int = 1
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = _nextId
        _nextId += 1
        return id
    }
}
