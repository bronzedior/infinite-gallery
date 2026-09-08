//
//  DiskImageCache.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 07/09/26.
//

import UIKit

struct DiskCacheResult {
    let image: UIImage
    let isStale: Bool
}

class DiskImageCache {
    static let shared = DiskImageCache()
    
    let ioQueue = DispatchQueue(label: "com.infinite-gallery.diskimagecache", qos: .utility)
    let directoryURL: URL
    let defaultMaxAge: TimeInterval = 60 * 60
    
    init() {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directoryURL = cachesURL.appendingPathComponent("ImageDiskCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
    
    func fileURL(for imageID: Int) -> URL {
        directoryURL.appendingPathComponent("\(imageID).jpg")
    }
    
    func get(for imageID: Int, maxAge: TimeInterval? = nil, completion: @escaping (DiskCacheResult?) -> Void) {
        let url = fileURL(for: imageID)
        let effectiveMaxAge = maxAge ?? defaultMaxAge
        
        ioQueue.async {
            guard let data = FileManager.default.contents(atPath: url.path),
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modDate = attrs?[.modificationDate] as? Date ?? .distantPast
            let isStale = Date().timeIntervalSince(modDate) > effectiveMaxAge
            
            DispatchQueue.main.async {
                completion(DiskCacheResult(image: image, isStale: isStale))
            }
        }
    }
    
    func set(_ image: UIImage, for imageID: Int) {
        let url = fileURL(for: imageID)
        ioQueue.async {
            guard let data = image.jpegData(compressionQuality: 0.9) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
