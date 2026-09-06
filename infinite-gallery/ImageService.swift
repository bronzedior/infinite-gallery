//
//  ImageService.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 04/09/26.
//

import UIKit

class ImageService {
    let fetchQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 4
        return q
    }()
    
    var operations: [Int: ImageFetchOperation] = [:]
    let lock = NSLock()
    
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
        
        let op = ImageFetchOperation(index: index, url: url) { idx, image, error in
            DispatchQueue.main.async {
                completion(idx, image, error)
            }
        }
        
        lock.lock()
        operations[index] = op
        lock.unlock()
        
        fetchQueue.addOperation(op)
    }
    
    func cancelFetch(at index: Int) {
        lock.lock()
        let op = operations.removeValue(forKey: index)
        lock.unlock()
        op?.cancel()
    }
    
    func cancelAllFetches() {
        lock.lock()
        let ops = Array(operations.values)
        operations.removeAll()
        lock.unlock()
        ops.forEach { $0.cancel() }
    }
}
