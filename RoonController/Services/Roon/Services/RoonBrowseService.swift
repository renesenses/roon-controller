import Foundation

// MARK: - Roon Browse Service

/// Wraps Roon browse API calls: browse hierarchy navigation, load items, search.
/// All JSON serialization happens before crossing the actor boundary.
struct RoonBrowseService: Sendable {

    let connection: RoonConnection
    let sessionKey: String

    init(connection: RoonConnection, sessionKey: String = "main") {
        self.connection = connection
        self.sessionKey = sessionKey
    }

    // MARK: - Browse

    struct BrowseResponse {
        let action: String?
        let list: [String: Any]?
        let items: [[String: Any]]

        // Sendable-safe initializer from raw data
        init(action: String?, listData: Data?, itemsData: Data?) {
            self.action = action
            if let listData = listData {
                self.list = (try? JSONSerialization.jsonObject(with: listData)) as? [String: Any]
            } else {
                self.list = nil
            }
            if let itemsData = itemsData {
                self.items = (try? JSONSerialization.jsonObject(with: itemsData)) as? [[String: Any]] ?? []
            } else {
                self.items = []
            }
        }

        init(action: String?, list: [String: Any]?, items: [[String: Any]]) {
            self.action = action
            self.list = list
            self.items = items
        }
    }

    func browse(
        hierarchy: String = "browse",
        zoneId: String? = nil,
        itemKey: String? = nil,
        input: String? = nil,
        popLevels: Int? = nil,
        popAll: Bool = false
    ) async throws -> BrowseResponse {
        let serviceName = await connection.browseService()

        var body: [String: Any] = [
            "hierarchy": hierarchy,
            "multi_session_key": sessionKey
        ]
        if let zoneId = zoneId { body["zone_or_output_id"] = zoneId }
        if let itemKey = itemKey { body["item_key"] = itemKey }
        if let input = input { body["input"] = input }
        if let popLevels = popLevels { body["pop_levels"] = popLevels }
        if popAll { body["pop_all"] = true }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let response = try await connection.sendRequestData(name: "\(serviceName)/browse", bodyData: bodyData)
        let json = response.bodyJSON ?? [:]

        let action = json["action"] as? String
        let list = json["list"] as? [String: Any]
        let listCount = (list?["count"] as? Int) ?? 0

        if listCount > 0 {
            let loadResult = try await load(hierarchy: hierarchy, offset: 0, count: 100)
            return BrowseResponse(action: action, list: list, items: loadResult.items)
        }

        return BrowseResponse(action: action, list: list, items: [])
    }

    // MARK: - Load

    struct LoadResponse {
        let list: [String: Any]?
        let items: [[String: Any]]
        let offset: Int

        init(list: [String: Any]?, items: [[String: Any]], offset: Int) {
            self.list = list
            self.items = items
            self.offset = offset
        }
    }

    func load(
        hierarchy: String = "browse",
        offset: Int = 0,
        count: Int = 100
    ) async throws -> LoadResponse {
        let serviceName = await connection.browseService()

        let body: [String: Any] = [
            "hierarchy": hierarchy,
            "multi_session_key": sessionKey,
            "offset": offset,
            "count": count
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let response = try await connection.sendRequestData(name: "\(serviceName)/load", bodyData: bodyData)
        let json = response.bodyJSON ?? [:]

        let list = json["list"] as? [String: Any]
        let items = json["items"] as? [[String: Any]] ?? []
        let resultOffset = json["offset"] as? Int ?? offset

        return LoadResponse(list: list, items: items, offset: resultOffset)
    }
}
