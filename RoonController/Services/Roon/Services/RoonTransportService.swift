import Foundation

// MARK: - Roon Transport Service

/// Wraps Roon transport API calls: playback control, seek, volume, settings, queue.
/// All JSON serialization happens before crossing the actor boundary.
struct RoonTransportService: Sendable {

    let connection: RoonConnection

    init(connection: RoonConnection) {
        self.connection = connection
    }

    // MARK: - Playback Control

    func control(zoneId: String, control: String) async throws {
        let serviceName = await connection.transportService()
        let body: [String: Any] = ["zone_or_output_id": zoneId, "control": control]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await connection.sendRequestData(name: "\(serviceName)/control", bodyData: bodyData)
    }

    // MARK: - Seek

    func seek(zoneId: String, how: String, seconds: Int) async throws {
        let serviceName = await connection.transportService()
        let body: [String: Any] = ["zone_or_output_id": zoneId, "how": how, "seconds": seconds]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await connection.sendRequestData(name: "\(serviceName)/seek", bodyData: bodyData)
    }

    // MARK: - Volume

    func changeVolume(outputId: String, how: String, value: Double) async throws {
        let serviceName = await connection.transportService()
        let body: [String: Any] = ["output_id": outputId, "how": how, "value": Int(value)]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await connection.sendRequestData(name: "\(serviceName)/change_volume", bodyData: bodyData)
    }

    // MARK: - Mute

    func mute(outputId: String, how: String) async throws {
        let serviceName = await connection.transportService()
        let body: [String: Any] = ["output_id": outputId, "how": how]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await connection.sendRequestData(name: "\(serviceName)/mute", bodyData: bodyData)
    }

    // MARK: - Settings

    func changeSettings(zoneId: String, settings: [String: any Sendable]) async throws {
        let serviceName = await connection.transportService()
        var body: [String: Any] = ["zone_or_output_id": zoneId]
        for (key, value) in settings { body[key] = value }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await connection.sendRequestData(name: "\(serviceName)/change_settings", bodyData: bodyData)
    }

    // MARK: - Queue

    func subscribeQueue(zoneId: String) async {
        await connection.subscribeQueue(zoneId: zoneId)
    }

    func playFromHere(zoneId: String, queueItemId: Int) async throws {
        let serviceName = await connection.transportService()
        let body: [String: Any] = ["zone_or_output_id": zoneId, "queue_item_id": queueItemId]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await connection.sendRequestData(name: "\(serviceName)/play_from_here", bodyData: bodyData)
    }
}
