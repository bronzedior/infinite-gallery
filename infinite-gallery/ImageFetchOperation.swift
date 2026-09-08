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
    
    let retryLock = NSLock()
    var currentAttempt = 0
    var reconnectToken: NetworkMonitor.SubscriptionToken?
    var pendingRetryWorkItem: DispatchWorkItem?
    
    let maxAttempts = 4
    let baseDelay: TimeInterval = 0.5
    
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
        
        attemptFetch(attempt: 0)
    }
    
    func attemptFetch(attempt: Int) {
        retryLock.lock()
        currentAttempt = attempt
        retryLock.unlock()
        
        guard !isCancelled else {
            finish()
            return
        }
        
        task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            guard !self.isCancelled else { self.finish(); return }
            
            let image = (data != nil) ? UIImage(data: data!) : nil
            
            // Cek apakah perlu retry
            if image == nil,
               self.shouldRetry(error: error, response: response, attempt: attempt) {
                self.scheduleRetry(for: attempt + 1)
            } else {
                //                DispatchQueue.main.async {
                //                    self.notifyCompletions(image: image, error: error)
                //                }
                //                self.finish()
                self.notifyCompletions(image: image, error: error)
                self.finish()
            }
        }
        
        task?.resume()
    }
    
    func shouldRetry(error: Error?, response: URLResponse?, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            
            if statusCode >= 500 && statusCode < 600 {
                return true
            }
            
            if statusCode >= 400 && statusCode < 500 {
                return false
            }
        }
        
        if let nsError = error as? NSError {
            let retryableErrorCodes: [Int] = [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorDNSLookupFailed,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
            ]
            
            if retryableErrorCodes.contains(nsError.code) {
                return true
            }
        }
        
        return false
    }
    
    func scheduleRetry(for nextAttempt: Int) {
        let delay = calculateBackoffDelay(for: nextAttempt - 1)
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard !self.isCancelled else { return }
            self.attemptFetch(attempt: nextAttempt)
        }
        
        retryLock.lock()
        pendingRetryWorkItem = workItem
        retryLock.unlock()
        
        if NetworkMonitor.shared.isConnected {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            scheduleRetryOnReconnect(workItem: workItem, fallbackDelay: delay)
        }
    }
    
    func calculateBackoffDelay(for attemptIndex: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * TimeInterval(1 << attemptIndex)
        
        let jitterFraction = 0.2
        let jitter = (Double.random(in: -jitterFraction...jitterFraction) + 1.0) * exponentialDelay
        
        return min(jitter, 8.0)
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
        
        retryLock.lock()
        pendingRetryWorkItem?.cancel()
        pendingRetryWorkItem = nil
        let token = reconnectToken
        reconnectToken = nil
        retryLock.unlock()
        
        if let token = token {
            NetworkMonitor.shared.removeStatusChangeCallback(token)
        }
    }
    
    func scheduleRetryOnReconnect(workItem: DispatchWorkItem, fallbackDelay: TimeInterval) {
        var reconnectCallbackFired = false
        let callbackLock = NSLock()
        var token: NetworkMonitor.SubscriptionToken?
        
        token = NetworkMonitor.shared.onStatusChange { [weak self] isConnected in
            guard let self = self else { return }
            
            callbackLock.lock()
            let shouldExecute = isConnected && !reconnectCallbackFired && !self.isCancelled
            if shouldExecute { reconnectCallbackFired = true }
            callbackLock.unlock()
            
            if let token = token {
                NetworkMonitor.shared.removeStatusChangeCallback(token)
            }
            
            if shouldExecute {
                DispatchQueue.global().async(execute: workItem)
            }
        }
        
        retryLock.lock()
        reconnectToken = token
        retryLock.unlock()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + fallbackDelay) { [weak self] in
            guard let self = self else { return }
            
            callbackLock.lock()
            let shouldExecute = !reconnectCallbackFired && !self.isCancelled
            if shouldExecute { reconnectCallbackFired = true }
            callbackLock.unlock()
            
            if let token = token {
                NetworkMonitor.shared.removeStatusChangeCallback(token)
            }
            
            if shouldExecute {
                workItem.perform()
            }
        }
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
