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
    
    // race condition??
    var operations: [Int: ImageFetchOperation] = [:]
    let lock = NSLock()
    
    func fetchImage(
        imageID: Int,
        at index: Int,
        width: Int,
        height: Int,
        completion: @escaping (Int, Int, UIImage?, Error?) -> Void
    ) {
        if !NetworkMonitor.shared.isConnected {
            DispatchQueue.main.async {
                let error = NSError(
                    domain: "ImageService",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Tidak ada koneksi internet"]
                )
                completion(index, imageID, nil, error)
            }
            return
        }
        
        guard CircuitBreaker.shared.canProceed() else {
            DispatchQueue.main.async {
                let error = NSError(
                    domain: "ImageService",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Server sedang bermasalah, coba lagi nanti"]
                )
                completion(index, imageID, nil, error)
            }
            return
        }
        
        //        let randomId = Int.random(in: 1...1000000)
        
        guard let url = URL(string: "https://picsum.photos/seed/\(imageID)/\(width)/\(height)") else {
            completion(index, imageID, nil, NSError(domain: "ImageService", code: -1))
            return
        }
        
        lock.lock()
        
        if let existing = operations[index],
           existing.imageID == imageID,
           existing.url == url,
           !existing.isCancelled,
           existing.addCompletion(completion) {
            lock.unlock()
            return // Coalesce: reuse existing request
        }
        
        operations[index]?.cancel()
        
        let op = ImageFetchOperation(index: index, imageID: imageID, url: url)
        let added = op.addCompletion(completion)
        assert(added, "addCompletion should succeed for newly created operation")
        
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
