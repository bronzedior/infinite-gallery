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
    
    @discardableResult
    func fetchImage(
        imageID: Int,
        at index: Int,
        width: Int,
        height: Int,
        completion: @escaping (Int, Int, UIImage?, Data?, Error?) -> Void
    ) -> ImageFetchOperation? {
        if !NetworkMonitor.shared.isConnected {
            DispatchQueue.main.async {
                completion(index, imageID, nil, nil, ImageLoadingState.ErrorType.noConnection)
            }
            return nil
        }
        
        guard CircuitBreaker.shared.canProceed() else {
            DispatchQueue.main.async {
                completion(index, imageID, nil, nil, ImageLoadingState.ErrorType.serverError)
            }
            return nil
        }
        
        guard width > 0, height > 0,
              let url = URL(string: "https://picsum.photos/seed/\(imageID)/\(width)/\(height)") else {
            DispatchQueue.main.async { completion(index, imageID, nil, nil, URLError(.badURL)) }
            return nil
        }
        
        lock.lock()
        
        if let existing = operations[index],
           existing.imageID == imageID,
           existing.url == url,
           !existing.isCancelled,
           existing.addCompletion(completion) {
            lock.unlock()
            return existing
        }
        
        operations[index]?.cancel()
        
        let op = ImageFetchOperation(index: index, imageID: imageID, url: url)
        let added = op.addCompletion(completion)
        assert(added, "addCompletion should succeed for newly created operation")
        
        operations[index] = op

        op.completionBlock = { [weak self, weak op] in
            guard let self, let op else { return }
            self.lock.lock()
            if self.operations[index] === op { self.operations.removeValue(forKey: index) }
            self.lock.unlock()
        }
        
        fetchQueue.addOperation(op)
        lock.unlock()
        return op
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
