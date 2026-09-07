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
    let completion: (Int, Int, UIImage?, Error?) -> Void
    var task: URLSessionDataTask?
    
    var _isExecuting = false
    var _isFinished = false
    
    override var isAsynchronous: Bool { true }
    override var isExecuting: Bool { _isExecuting }
    override var isFinished: Bool { _isFinished }
    
    init(index: Int, imageID: Int, url: URL, completion: @escaping (Int, Int, UIImage?, Error?) -> Void) {
        self.index = index
        self.imageID = imageID
        self.url = url
        self.completion = completion
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
            
            if let data = data, let image = UIImage(data: data) {
                self.completion(self.index, self.imageID, image, nil)
            } else {
                self.completion(self.index, self.imageID, nil, error)
            }
        }
        
        task?.resume()
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
