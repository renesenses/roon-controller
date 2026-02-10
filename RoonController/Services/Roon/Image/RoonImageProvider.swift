import Foundation

// MARK: - Roon Image Provider

/// Coordinates image fetching from Roon Core with the two-tier cache.
/// Used by LocalImageServer to serve images to SwiftUI AsyncImage views.
actor RoonImageProvider {

    static let shared = RoonImageProvider()

    private var imageService: RoonImageService?
    private var inFlightRequests: [String: Task<Data?, Never>] = [:]

    // MARK: - Configuration

    func setImageService(_ service: RoonImageService?) {
        self.imageService = service
    }

    // MARK: - Fetch Image

    /// Fetch an image by key and dimensions. Returns cached data or fetches from Core.
    func fetchImage(key: String, width: Int = 300, height: Int = 300) async -> Data? {
        let cacheKey = RoonImageCache.cacheKey(imageKey: key, width: width, height: height)

        // Check cache first
        if let cached = await RoonImageCache.shared.get(key: cacheKey) {
            return cached
        }

        // Deduplicate in-flight requests
        if let existing = inFlightRequests[cacheKey] {
            return await existing.value
        }

        let task = Task<Data?, Never> { [weak self] in
            guard let self = self else { return nil }
            let service = await self.imageService
            guard let service = service else { return nil }

            let options = RoonImageService.ImageOptions(
                scale: "fit",
                width: width,
                height: height,
                format: "image/jpeg"
            )

            do {
                if let data = try await service.getImage(key: key, options: options), !data.isEmpty {
                    await RoonImageCache.shared.store(key: cacheKey, data: data)
                    return data
                }
            } catch {
                // Fetch failed
            }
            return nil
        }

        inFlightRequests[cacheKey] = task
        let result = await task.value
        inFlightRequests.removeValue(forKey: cacheKey)
        return result
    }
}
