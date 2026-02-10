import Foundation

// MARK: - Roon Status Service (Provided)

/// Service provided by this extension to the Roon Core.
/// Responds to ping requests and provides extension status.
/// Note: Most of this is handled directly in RoonConnection's handleCoreRequest,
/// but this struct provides the message formatting utilities.
struct RoonStatusService {

    /// Build a ping response.
    static func pingResponse(requestId: Int) -> Data {
        MOOMessage.complete(name: "Success", requestId: requestId)
    }

    /// Build a status subscription response.
    static func statusResponse(requestId: Int, message: String = "Ready", isError: Bool = false) -> Data {
        let body = RoonRegistration.statusBody(message: message, isError: isError)
        let jsonData = try? JSONSerialization.data(withJSONObject: body)
        return MOOMessage.complete(name: "Subscribed", requestId: requestId, body: jsonData)
    }

    /// Build a status update (CONTINUE) for an active subscription.
    static func statusUpdate(requestId: Int, message: String, isError: Bool = false) -> Data {
        let body = RoonRegistration.statusBody(message: message, isError: isError)
        let jsonData = try? JSONSerialization.data(withJSONObject: body)
        return MOOMessage.continueMessage(name: "Changed", requestId: requestId, body: jsonData)
    }
}
