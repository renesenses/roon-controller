import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.bertrand.RoonController", category: "LocalImageServer")

// MARK: - Local Image Server

/// Minimal HTTP server on localhost that serves Roon images to SwiftUI AsyncImage views.
/// URL format: `http://localhost:{port}/image/{key}?width=N&height=N`
/// Tries ports 9150-9159 to avoid conflicts (e.g. Roon Core on the same machine).
actor LocalImageServer {

    static let shared = LocalImageServer()
    private static let basePort: UInt16 = 9150
    private static let maxPortRetries = 10

    /// Thread-safe published port for synchronous access from SwiftUI views.
    nonisolated(unsafe) static private(set) var currentPort: UInt16 = basePort

    private var listener: NWListener?
    private var isRunning = false

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        for offset in 0..<UInt16(Self.maxPortRetries) {
            let port = Self.basePort + offset
            do {
                let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
                self.listener = listener
                Self.currentPort = port

                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        logger.info("Image server listening on port \(port)")
                        Task { await self?.setRunning(true) }
                    case .failed(let error):
                        logger.warning("Image server failed on port \(port): \(error.localizedDescription)")
                        Task { await self?.restart() }
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    Task { await self?.handleConnection(connection) }
                }

                listener.start(queue: .global(qos: .utility))
                logger.info("Image server starting on port \(port)")
                return // success — stop trying other ports
            } catch {
                logger.warning("Port \(port) unavailable: \(error.localizedDescription)")
                continue
            }
        }
        logger.error("Image server failed to bind any port in range \(Self.basePort)-\(Self.basePort + UInt16(Self.maxPortRetries) - 1)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func setRunning(_ value: Bool) {
        isRunning = value
    }

    private func restart() {
        stop()
        start()
    }

    // MARK: - URL Generation

    /// Generate a URL for an image served by this local server (synchronous, no await needed).
    nonisolated static func imageURL(key: String, width: Int = 300, height: Int = 300) -> URL? {
        URL(string: "http://localhost:\(currentPort)/image/\(key)?width=\(width)&height=\(height)")
    }

    // MARK: - Connection Handling

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
            guard let data = data, error == nil else {
                connection.cancel()
                return
            }

            guard let request = String(data: data, encoding: .utf8) else {
                Self.sendResponse(connection: connection, status: 400, body: Data("Bad Request".utf8))
                return
            }

            Task {
                await Self.handleHTTPRequest(request, connection: connection)
            }
        }
    }

    // MARK: - HTTP Request Parsing

    private static func handleHTTPRequest(_ request: String, connection: NWConnection) async {
        // Parse: GET /image/{key}?width=N&height=N HTTP/1.1
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: Data("Bad Request".utf8))
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendResponse(connection: connection, status: 405, body: Data("Method Not Allowed".utf8))
            return
        }

        let pathAndQuery = String(parts[1])
        guard pathAndQuery.hasPrefix("/image/") else {
            sendResponse(connection: connection, status: 404, body: Data("Not Found".utf8))
            return
        }

        // Extract key and query params
        let pathWithoutPrefix = String(pathAndQuery.dropFirst("/image/".count))
        let components = pathWithoutPrefix.split(separator: "?", maxSplits: 1)
        let key = String(components[0])

        var width = 300
        var height = 300

        if components.count > 1 {
            let queryString = String(components[1])
            let queryParams = parseQueryParams(queryString)
            if let w = queryParams["width"], let wInt = Int(w) { width = wInt }
            if let h = queryParams["height"], let hInt = Int(h) { height = hInt }
        }

        guard !key.isEmpty else {
            sendResponse(connection: connection, status: 400, body: Data("Missing image key".utf8))
            return
        }

        // Fetch image
        if let imageData = await RoonImageProvider.shared.fetchImage(key: key, width: width, height: height) {
            sendResponse(
                connection: connection,
                status: 200,
                contentType: "image/jpeg",
                cacheControl: "public, max-age=86400",
                body: imageData
            )
        } else {
            sendResponse(connection: connection, status: 404, body: Data("Image not found".utf8))
        }
    }

    private static func parseQueryParams(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0])] = String(kv[1])
            }
        }
        return params
    }

    // MARK: - HTTP Response

    private static func sendResponse(
        connection: NWConnection,
        status: Int,
        contentType: String = "text/plain",
        cacheControl: String? = nil,
        body: Data
    ) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Error"
        }

        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        if let cache = cacheControl {
            header += "Cache-Control: \(cache)\r\n"
        }
        header += "Connection: close\r\n"
        header += "\r\n"

        var responseData = Data(header.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
