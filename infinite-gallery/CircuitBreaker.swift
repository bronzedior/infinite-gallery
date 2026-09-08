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

    struct SubscriptionToken: Hashable {
        let id = UUID()
    }

    let lock = NSLock()
    var state: State = .closed
    var consecutiveFailures = 0
    var openedAt: Date?
    var halfOpenStartedAt: Date?
    var currentOpenDuration: TimeInterval = 15

    let failureThreshold = 5
    let baseOpenDuration: TimeInterval = 15
    let maxOpenDuration: TimeInterval = 60
    let halfOpenTimeout: TimeInterval = 10

    var recoveryCallbacks: [SubscriptionToken: () -> Void] = [:]
    let recoveryCallbackLock = NSLock()

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
            halfOpenStartedAt = Date()
            return true
        case .halfOpen:
            if let startedAt = halfOpenStartedAt,
               Date().timeIntervalSince(startedAt) >= halfOpenTimeout {
                state = .open
                openedAt = Date()
                currentOpenDuration = min(currentOpenDuration * 2, maxOpenDuration)
                halfOpenStartedAt = nil
            }
            return false
        }
    }

    func recordSuccess() {
        lock.lock()
        let wasRecovering = state != .closed
        consecutiveFailures = 0
        state = .closed
        currentOpenDuration = baseOpenDuration
        halfOpenStartedAt = nil
        lock.unlock()

        if wasRecovering {
            notifyRecovery()
        }
    }

    func recordFailure() {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .halfOpen:
            state = .open
            openedAt = Date()
            currentOpenDuration = min(currentOpenDuration * 2, maxOpenDuration)
            halfOpenStartedAt = nil
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

    @discardableResult
    func onRecover(_ callback: @escaping () -> Void) -> SubscriptionToken {
        let token = SubscriptionToken()
        recoveryCallbackLock.lock()
        recoveryCallbacks[token] = callback
        recoveryCallbackLock.unlock()
        return token
    }

    func removeRecoveryCallback(_ token: SubscriptionToken) {
        recoveryCallbackLock.lock()
        recoveryCallbacks.removeValue(forKey: token)
        recoveryCallbackLock.unlock()
    }

    func notifyRecovery() {
        recoveryCallbackLock.lock()
        let callbacks = Array(recoveryCallbacks.values)
        recoveryCallbackLock.unlock()

        DispatchQueue.main.async {
            callbacks.forEach { $0() }
        }
    }
}
