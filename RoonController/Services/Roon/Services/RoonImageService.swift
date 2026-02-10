import Foundation

// MARK: - Roon Image Service

/// Fetches images from Roon Core via the MOO image API.
/// Images are returned as raw binary data (JPEG or PNG).
struct RoonImageService: Sendable {

    let connection: RoonConnection

    init(connection: RoonConnection) {
        self.connection = connection
    }

    // MARK: - Get Image

    struct ImageOptions: Sendable {
        var scale: String = "fit"
        var width: Int = 300
        var height: Int = 300
        var format: String = "image/jpeg"
    }

    /// Fetch an image from Roon Core by its image key.
    func getImage(key: String, options: ImageOptions = ImageOptions()) async throws -> Data? {
        let serviceName = await connection.imageService()

        let body: [String: Any] = [
            "image_key": key,
            "scale": options.scale,
            "width": options.width,
            "height": options.height,
            "format": options.format
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let response = try await connection.sendRequestData(name: "\(serviceName)/get_image", bodyData: bodyData)
        return response.body
    }
}
