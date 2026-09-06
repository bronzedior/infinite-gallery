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
    
    func set(_ image: UIImage, for index: Int) {
        let cost = Int(image.size.width * image.size.height * 4)
        queue.async(flags: .barrier) {
            self.cache.setObject(image, forKey: NSNumber(value: index), cost: cost)
        }
    }
    
    func get(for index: Int) -> UIImage? {
        var image: UIImage?
        queue.sync {
            image = self.cache.object(forKey: NSNumber(value: index))
        }
        return image
    }
    
    func remove(for index: Int) {
        queue.async(flags: .barrier) {
            self.cache.removeObject(forKey: NSNumber(value: index))
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
