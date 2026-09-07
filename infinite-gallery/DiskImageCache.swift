//
//  DiskImageCache.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 07/09/26.
//

import UIKit

class DiskImageCache {
    static let shared = DiskImageCache()

    let ioQueue = DispatchQueue(label: "com.infinite-gallery.diskimagecache", qos: .utility)
    let directoryURL: URL

    init() {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directoryURL = cachesURL.appendingPathComponent("ImageDiskCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func fileURL(for imageID: Int) -> URL {
        directoryURL.appendingPathComponent("\(imageID).jpg")
    }

    func get(for imageID: Int, completion: @escaping (UIImage?) -> Void) {
        let url = fileURL(for: imageID)
        ioQueue.async {
            let data = FileManager.default.contents(atPath: url.path)
            let image = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async { completion(image) }
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
