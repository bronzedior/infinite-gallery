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
    var completions: [(Int, Int, UIImage?, Data?, Error?) -> Void] = []
    var didNotify = false
    
    private var task: URLSessionDataTask?
    
    private let stateLock = NSRecursiveLock()
    private var _isExecuting = false
    private var _isFinished = false
    
    override var isAsynchronous: Bool { true }
    override var isExecuting: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isExecuting
    }
    override var isFinished: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isFinished
    }
    
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
    
    func addCompletion(_ completion: @escaping (Int, Int, UIImage?, Data?, Error?) -> Void) -> Bool {
        completionLock.lock()
        defer { completionLock.unlock() }
        
        if didNotify || isCancelled {
            return false
        }
        completions.append(completion)
        return true
    }
    
    override func start() {
        stateLock.lock()
        guard !isCancelled, !_isFinished else {
            finish()
            stateLock.unlock()
            return
        }
        
        willChangeValue(forKey: "isExecuting")
        _isExecuting = true
        didChangeValue(forKey: "isExecuting")
        stateLock.unlock()
        
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
        
        stateLock.lock()
        guard !isCancelled, !_isFinished else {
            stateLock.unlock()
            finish()
            return
        }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            guard !self.isCancelled else { self.finish(); return }
            
            let validStatus = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let image = error == nil && validStatus ? data.flatMap { UIImage(data: $0) } : nil
            let resultError = error ?? (validStatus ? ImageLoadingState.ErrorType.decodeFailed : .serverError)
            
            self.recordCircuitBreakerOutcome(image: image, response: response, error: error)
            
            if image == nil,
               self.shouldRetry(error: error, response: response, attempt: attempt) {
                self.scheduleRetry(for: attempt + 1)
            } else {
                self.notifyCompletions(image: image, data: image == nil ? nil : data, error: image == nil ? resultError : nil)
                self.finish()
            }
        }
        
        self.task = task
        task.resume()
        stateLock.unlock()
    }
    
    func shouldRetry(error: Error?, response: URLResponse?, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            
            if statusCode >= 500 && statusCode < 600 {
                return !CircuitBreaker.shared.isOpen
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
                return !CircuitBreaker.shared.isOpen
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
        guard !isCancelled else {
            retryLock.unlock()
            return
        }
        pendingRetryWorkItem = workItem
        retryLock.unlock()
        
        if NetworkMonitor.shared.isConnected {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: workItem)
        } else {
            scheduleRetryOnReconnect(workItem: workItem, fallbackDelay: delay)
        }
    }
    
    func calculateBackoffDelay(for attemptIndex: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2, Double(max(0, attemptIndex)))
        
        let jitterFraction = 0.2
        let jitter = (Double.random(in: -jitterFraction...jitterFraction) + 1.0) * exponentialDelay
        
        return min(jitter, 8.0)
    }
    
    func notifyCompletions(image: UIImage?, data: Data? = nil, error: Error?) {
        completionLock.lock()
        guard !didNotify else {
            completionLock.unlock()
            return
        }
        let callbackList = completions
        completions.removeAll()
        didNotify = true
        completionLock.unlock()
        
        DispatchQueue.main.async {
            for callback in callbackList {
                callback(self.index, self.imageID, image, data, error)
            }
        }
    }
    
    // jika user scroll terlalu cepat
    override func cancel() {
        super.cancel()
        stateLock.lock()
        let task = self.task
        self.task = nil
        stateLock.unlock()
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
        notifyCompletions(image: nil, error: URLError(.cancelled))
        finish()
    }
    
    func scheduleRetryOnReconnect(workItem: DispatchWorkItem, fallbackDelay: TimeInterval) {
        var reconnectCallbackFired = false
        let callbackLock = NSLock()
        var token: NetworkMonitor.SubscriptionToken?
        
        let subscription = NetworkMonitor.shared.onStatusChange { [weak self] isConnected in
            guard let self = self else { return }
            
            callbackLock.lock()
            let shouldExecute = isConnected && !reconnectCallbackFired && !self.isCancelled
            if shouldExecute { reconnectCallbackFired = true }
            let currentToken = token
            callbackLock.unlock()
            
            if shouldExecute {
                if let currentToken { NetworkMonitor.shared.removeStatusChangeCallback(currentToken) }
                DispatchQueue.global().async(execute: workItem)
            }
        }

        callbackLock.lock()
        token = subscription
        let alreadyFired = reconnectCallbackFired
        callbackLock.unlock()
        if alreadyFired { NetworkMonitor.shared.removeStatusChangeCallback(subscription) }
        
        retryLock.lock()
        if isCancelled {
            retryLock.unlock()
            NetworkMonitor.shared.removeStatusChangeCallback(subscription)
            return
        }
        reconnectToken = subscription
        retryLock.unlock()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + fallbackDelay) { [weak self] in
            guard let self = self else { return }
            
            callbackLock.lock()
            let shouldExecute = !reconnectCallbackFired && !self.isCancelled
            if shouldExecute { reconnectCallbackFired = true }
            let currentToken = token
            callbackLock.unlock()
            
            if let currentToken {
                NetworkMonitor.shared.removeStatusChangeCallback(currentToken)
            }
            
            if shouldExecute {
                workItem.perform()
            }
        }
    }
    
    func recordCircuitBreakerOutcome(image: UIImage?, response: URLResponse?, error: Error?) {
        if image != nil {
            CircuitBreaker.shared.recordSuccess()
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse, (500..<600).contains(httpResponse.statusCode) {
            CircuitBreaker.shared.recordFailure()
            return
        }
        
        if let nsError = error as? NSError, NetworkMonitor.shared.isConnected {
            let hostUnreachableCodes: [Int] = [
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed
            ]
            if hostUnreachableCodes.contains(nsError.code) {
                CircuitBreaker.shared.recordFailure()
            }
        }
    }
    
    func finish() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !_isFinished else { return }

        willChangeValue(forKey: "isExecuting")
        willChangeValue(forKey: "isFinished")
        
        _isExecuting = false
        _isFinished = true
        task = nil
        
        didChangeValue(forKey: "isFinished")
        didChangeValue(forKey: "isExecuting")
    }
}
