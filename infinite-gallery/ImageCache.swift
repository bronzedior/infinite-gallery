//
//  ImageCache.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 06/09/26.
//

import UIKit

class ImageCache {
    static let shared = ImageCache()
    
    let cache = NSCache<NSNumber, UIImage>()
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
    
    func set(_ image: UIImage, for imageID: Int) {
        // hipotesis: retina display scale
        // iphone 17 retina display pixels = 1206 x 2622 (3x scale)
        // non-retina equivalent = 402 x 874
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        queue.async(flags: .barrier) {
            self.cache.setObject(image, forKey: NSNumber(value: imageID), cost: cost)
        }
    }
    
    func get(for imageID: Int) -> UIImage? {
        var image: UIImage?
        queue.sync {
            image = self.cache.object(forKey: NSNumber(value: imageID))
        }
        return image
    }
    
    func remove(for imageID: Int) {
        queue.async(flags: .barrier) {
            self.cache.removeObject(forKey: NSNumber(value: imageID))
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
