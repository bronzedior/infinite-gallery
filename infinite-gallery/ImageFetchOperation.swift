//
//  ImageFetchOperation.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 06/09/26.
//

import UIKit

class ImageFetchOperation: Operation, @unchecked Sendable {
    let index: Int
    let imageID: Int
    let url: URL
    
    let completionLock = NSLock()
    var completions: [(Int, Int, UIImage?, Error?) -> Void] = []
    var didNotify = false
    
    var task: URLSessionDataTask?
    
    var _isExecuting = false
    var _isFinished = false
    
    override var isAsynchronous: Bool { true }
    override var isExecuting: Bool { _isExecuting }
    override var isFinished: Bool { _isFinished }
    
    init(index: Int, imageID: Int, url: URL) {
        self.index = index
        self.imageID = imageID
        self.url = url
    }
    
    func addCompletion(_ completion: @escaping (Int, Int, UIImage?, Error?) -> Void) -> Bool {
        completionLock.lock()
        defer { completionLock.unlock() }
        
        if didNotify || isCancelled {
            return false
        }
        completions.append(completion)
        return true
    }
    
    override func start() {
        guard !isCancelled else { finish(); return }
        
        willChangeValue(forKey: "isExecuting")
        _isExecuting = true
        didChangeValue(forKey: "isExecuting")
        
        task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            
            defer { self.finish() }
            
            guard !self.isCancelled else { return }
            
            let image = (data != nil) ? UIImage(data: data!) : nil
            self.notifyCompletions(image: image, error: error)
        }
        
        task?.resume()
    }
    
    func notifyCompletions(image: UIImage?, error: Error?) {
        completionLock.lock()
        let callbackList = completions
        completions.removeAll()
        didNotify = true
        completionLock.unlock()
        
        DispatchQueue.main.async {
            for callback in callbackList {
                callback(self.index, self.imageID, image, error)
            }
        }
    }
    
    // jika user scroll terlalu cepat
    override func cancel() {
        super.cancel()
        task?.cancel()
    }
    
    func finish() {
        willChangeValue(forKey: "isExecuting")
        willChangeValue(forKey: "isFinished")
        
        _isExecuting = false
        _isFinished = true
        
        didChangeValue(forKey: "isExecuting")
        didChangeValue(forKey: "isFinished")
    }
}
