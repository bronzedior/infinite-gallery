//
//  ImageCache.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 06/09/26.
//

import UIKit

class ImageCache {
    static let shared = ImageCache()
    
    let cache = NSCache<NSString, UIImage>()
    let queue = DispatchQueue(label: "com.infinite-gallery.imagecache", attributes: .concurrent)
    
    init() {
        cache.totalCostLimit = 50 * 1024 * 1024
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func set(_ image: UIImage, for key: ImageRequestKey) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        queue.async(flags: .barrier) {
            self.cache.setObject(image, forKey: key.cacheKey as NSString, cost: cost)
        }
    }
    
    func get(for key: ImageRequestKey) -> UIImage? {
        var image: UIImage?
        queue.sync {
            image = self.cache.object(forKey: key.cacheKey as NSString)
        }
        return image
    }
    
    func remove(for key: ImageRequestKey) {
        queue.async(flags: .barrier) {
            self.cache.removeObject(forKey: key.cacheKey as NSString)
        }
    }
    
    func removeAll() {
        queue.async(flags: .barrier) {
            self.cache.removeAllObjects()
        }
    }
    
    @objc func handleMemoryWarning() {
        removeAll()
    }
}
