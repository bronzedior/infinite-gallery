//
//  ImageService.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 04/09/26.
//

import UIKit

class ImageService {
    let cache = NSCache<NSString, UIImage>()
    var activeTasks: [Int: URLSessionDataTask] = [:]
    let queue = DispatchQueue(label: "com.imagegallery.service")
    
    func fetchImage(
        at index: Int,
        width: Int,
        height: Int,
        completion: @escaping (Int, UIImage?, Error?) -> Void
    ) {
        let randomId = Int.random(in: 1...1000000)
        
        guard let url = URL(string: "https://picsum.photos/\(width)/\(height)?random=\(randomId)") else {
            completion(index, nil, NSError(domain: "ImageService", code: -1))
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            defer {
                self?.queue.sync {
                    self?.activeTasks[index] = nil
                }
            }
            
            DispatchQueue.main.async {
                if let data = data, let image = UIImage(data: data) {
                    completion(index, image, nil)
                } else {
                    completion(index, nil, error ?? NSError(domain: "ImageService", code: -2))
                }
            }
        }
        
        queue.sync {
            activeTasks[index] = task
        }
        
        task.resume()
    }
    
    func cancelFetch(at index: Int) {
        queue.sync {
            activeTasks.removeValue(forKey: index)?.cancel()
        }
    }
    
    func cancelAllFetches() {
        queue.sync {
            activeTasks.values.forEach { $0.cancel() }
            activeTasks.removeAll()
        }
    }
}
