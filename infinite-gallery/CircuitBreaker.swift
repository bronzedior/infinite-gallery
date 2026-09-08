//
//  CircuitBreaker.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 08/09/26.
//

import Foundation

class CircuitBreaker {
    static let shared = CircuitBreaker()
    
    enum State {
        case closed
        case open
        case halfOpen
    }
    
    let lock = NSLock()
    var state: State = .closed
    var consecutiveFailures = 0
    var openedAt: Date?
    var currentOpenDuration: TimeInterval = 15
    
    let failureThreshold = 5
    let baseOpenDuration: TimeInterval = 15
    let maxOpenDuration: TimeInterval = 60
    
    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .closed = state { return false }
        return true
    }
    
    func canProceed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        switch state {
        case .closed:
            return true
        case .open:
            guard let openedAt = openedAt,
                  Date().timeIntervalSince(openedAt) >= currentOpenDuration else {
                return false
            }
            state = .halfOpen
            return true
        case .halfOpen:
            return false
        }
    }
    
    func recordSuccess() {
        lock.lock()
        defer { lock.unlock() }
        consecutiveFailures = 0
        state = .closed
        currentOpenDuration = baseOpenDuration
    }
    
    func recordFailure() {
        lock.lock()
        defer { lock.unlock() }
        
        switch state {
        case .halfOpen:
            state = .open
            openedAt = Date()
            currentOpenDuration = min(currentOpenDuration * 2, maxOpenDuration)
        case .closed:
            consecutiveFailures += 1
            if consecutiveFailures >= failureThreshold {
                state = .open
                openedAt = Date()
                currentOpenDuration = baseOpenDuration
            }
        case .open:
            break
        }
    }
}
