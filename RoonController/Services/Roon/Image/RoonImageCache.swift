import Foundation

// MARK: - Roon Image Cache

/// Two-tier image cache: NSCache (memory) + disk cache in app's Caches directory.
/// Cache keys are derived from image_key + dimensions.
actor RoonImageCache {

    static let shared = RoonImageCache()

    // MARK: - Memory Cache

    private let memoryCache = NSCache<NSString, NSData>()
    private let maxMemoryItems = 200

    // MARK: - Disk Cache

    private let diskCacheDir: URL
    private let maxDiskAge: TimeInterval = 7 * 24 * 3600 // 7 days

    init() {
        let cacheBase: URL
        if let container = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheBase = container
        } else {
            cacheBase = FileManager.default.temporaryDirectory
        }
        diskCacheDir = cacheBase.appendingPathComponent("RoonImages", isDirectory: true)

        memoryCache.countLimit = maxMemoryItems

        // Create disk cache directory
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Cache Key

    static func cacheKey(imageKey: String, width: Int, height: Int) -> String {
        "\(imageKey)_\(width)x\(height)"
    }

    // MARK: - Get

    func get(key: String) -> Data? {
        // Check memory cache first
        if let data = memoryCache.object(forKey: key as NSString) {
            return data as Data
        }

        // Check disk cache
        let fileURL = diskCacheDir.appendingPathComponent(safeFileName(key))
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        // Check age
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > maxDiskAge {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        // Promote to memory cache
        memoryCache.setObject(data as NSData, forKey: key as NSString)
        return data
    }

    // MARK: - Store

    func store(key: String, data: Data) {
        // Memory cache
        memoryCache.setObject(data as NSData, forKey: key as NSString)

        // Disk cache
        let fileURL = diskCacheDir.appendingPathComponent(safeFileName(key))
        try? data.write(to: fileURL)
    }

    // MARK: - Eviction

    func evictExpired() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let now = Date()
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let modDate = attrs[.modificationDate] as? Date,
               now.timeIntervalSince(modDate) > maxDiskAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheDir)
        try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Helpers

    private func safeFileName(_ key: String) -> String {
        // Use a hash to avoid filesystem issues with special characters
        let hash = key.data(using: .utf8)!.withUnsafeBytes { bytes -> String in
            var hasher = Hasher()
            hasher.combine(bytes: UnsafeRawBufferPointer(bytes))
            let value = hasher.finalize()
            return String(format: "%016lx", abs(value))
        }
        return hash
    }
}
