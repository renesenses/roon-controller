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

        // Auto-trim if a size limit is configured
        let maxMB = UserDefaults.standard.integer(forKey: "cache_max_size_mb")
        if maxMB > 0 {
            trimDiskCache(toSizeLimit: Int64(maxMB) * 1_000_000)
        }
    }

    // MARK: - Disk Cache Size

    func diskCacheSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheDir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    func trimDiskCache(toSizeLimit maxBytes: Int64) {
        evictExpired()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        // Gather file info
        struct FileInfo {
            let url: URL
            let size: Int64
            let modDate: Date
        }

        var infos: [FileInfo] = []
        var totalSize: Int64 = 0
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64,
               let modDate = attrs[.modificationDate] as? Date {
                infos.append(FileInfo(url: file, size: size, modDate: modDate))
                totalSize += size
            }
        }

        guard totalSize > maxBytes else { return }

        // Sort oldest first
        infos.sort { $0.modDate < $1.modDate }

        for info in infos {
            guard totalSize > maxBytes else { break }
            try? FileManager.default.removeItem(at: info.url)
            totalSize -= info.size
        }
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
