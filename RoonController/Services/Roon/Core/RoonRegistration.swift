import Foundation

// MARK: - Roon Registration

/// Handles the Roon extension registration handshake and token persistence.
/// The handshake flow:
/// 1. Send `registry:1/info` → receive Core info
/// 2. Send `registry:1/register` with extension info + optional saved token
/// 3. Receive `Registered` with token to persist, or `NotRegistered`
struct RoonRegistration {

    // MARK: - Extension Info

    static let extensionId = "com.bertrand.rooncontroller"
    static let displayName = "Roon Controller macOS"
    static let displayVersion = "1.0.3"
    static let publisher = "Bertrand"
    static let email = ""

    // MARK: - Token Persistence

    private static let tokenKey = "roon_core_token"
    private static let pairedCoreIdKey = "roon_paired_core_id"

    static func savedToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static func saveToken(_ token: String, coreId: String? = nil) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        if let coreId = coreId {
            UserDefaults.standard.set(coreId, forKey: pairedCoreIdKey)
        }
    }

    static func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: pairedCoreIdKey)
    }

    static func savedCoreId() -> String? {
        UserDefaults.standard.string(forKey: pairedCoreIdKey)
    }

    // MARK: - Registration Payloads

    /// Build the `registry:1/info` request body.
    static func infoRequestBody() -> [String: Any] {
        [:]
    }

    /// Build the `registry:1/register` request body.
    static func registerRequestBody() -> [String: Any] {
        var body: [String: Any] = [
            "extension_id": extensionId,
            "display_name": displayName,
            "display_version": displayVersion,
            "publisher": publisher,
            "email": email,
            "required_services": [
                "com.roonlabs.transport:2",
                "com.roonlabs.browse:1",
                "com.roonlabs.image:1"
            ],
            "optional_services": [] as [String],
            "provided_services": [
                "com.roonlabs.ping:1",
                "com.roonlabs.status:1"
            ],
            "website": ""
        ]

        if let token = savedToken() {
            body["token"] = token
        }

        return body
    }

    // MARK: - Response Handling

    enum RegistrationResult {
        case registered(token: String, coreId: String, coreName: String)
        case notRegistered
    }

    /// Parse a registration response from the Core.
    static func parseRegistrationResponse(_ body: [String: Any]?) -> RegistrationResult {
        guard let body = body else { return .notRegistered }

        if let token = body["token"] as? String {
            let coreId = body["core_id"] as? String ?? ""
            let coreName = body["display_name"] as? String ?? ""
            return .registered(token: token, coreId: coreId, coreName: coreName)
        }

        return .notRegistered
    }

    /// Build the status message body for provided status service.
    static func statusBody(message: String = "Ready", isError: Bool = false) -> [String: Any] {
        [
            "message": message,
            "is_error": isError
        ]
    }
}
