import UIKit

struct DiskCacheResult {
    let image: UIImage
    let isStale: Bool
}

class DiskImageCache {
    static let shared = DiskImageCache()

    let ioQueue = DispatchQueue(label: "com.infinite-gallery.diskimagecache", qos: .utility)
    let directoryURL: URL
    let maxBytes: Int
    let defaultMaxAge: TimeInterval = 60 * 60

    init(directoryURL: URL? = nil, maxBytes: Int = 100 * 1024 * 1024) {
        precondition(maxBytes >= 0)
        self.maxBytes = maxBytes
        self.directoryURL = directoryURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageDiskCache", isDirectory: true)
        ioQueue.async {
            do {
                try FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
                try self.trim()
            } catch {
                NSLog("Disk cache initialization failed: %@", error.localizedDescription)
            }
        }
    }

    func fileURL(for key: ImageRequestKey) -> URL {
        directoryURL.appendingPathComponent("\(key.cacheKey).image")
    }

    func get(for key: ImageRequestKey, maxAge: TimeInterval? = nil, completion: @escaping (DiskCacheResult?) -> Void) {
        let url = fileURL(for: key)
        let effectiveMaxAge = maxAge ?? defaultMaxAge
        ioQueue.async {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modDate = attrs?[.modificationDate] as? Date ?? .distantPast
            let isStale = Date().timeIntervalSince(modDate) > effectiveMaxAge
            DispatchQueue.main.async { completion(DiskCacheResult(image: image, isStale: isStale)) }
        }
    }

    func set(_ data: Data, for key: ImageRequestKey) {
        guard data.count <= maxBytes else { return }
        ioQueue.async {
            do {
                try data.write(to: self.fileURL(for: key), options: .atomic)
                try self.trim()
            } catch {
                NSLog("Disk cache write failed: %@", error.localizedDescription)
            }
        }
    }

    private func trim() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        let entries = try files.compactMap { url -> (url: URL, size: Int, date: Date)? in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.date < $1.date }) where total > maxBytes {
            try FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
