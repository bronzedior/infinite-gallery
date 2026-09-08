//
//  NetworkMonitor.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 07/09/26.
//

import Foundation
import Network

class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "com.infinite-gallery.networkmonitor")
    
    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }
    
    var interfaceType: InterfaceType {
        lock.lock()
        defer { lock.unlock() }
        return _interfaceType
    }
    
    let lock = NSLock()
    var _isConnected = true
    var _interfaceType: InterfaceType = .unknown
    
    struct SubscriptionToken: Hashable {
        let id = UUID()
    }
    var statusChangeCallbacks: [SubscriptionToken: (Bool) -> Void] = [:]
    let callbackLock = NSLock()
    
    enum InterfaceType {
        case wifi
        case cellular
        case other
        case unknown
    }
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updatePath(path)
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
    
    func updatePath(_ path: NWPath) {
        let connected = path.status == .satisfied
        let type = extractInterfaceType(from: path)
        
        lock.lock()
        let statusChanged = (_isConnected != connected)
        _isConnected = connected
        _interfaceType = type
        lock.unlock()
        
        if statusChanged {
            notifyStatusChange(connected)
        }
    }
    
    func extractInterfaceType(from path: NWPath) -> InterfaceType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) ||
                    path.usesInterfaceType(.loopback) {
            return .other
        } else {
            return .unknown
        }
    }
    
    @discardableResult
    func onStatusChange(_ callback: @escaping (Bool) -> Void) -> SubscriptionToken {
        let token = SubscriptionToken()
        callbackLock.lock()
        statusChangeCallbacks[token] = callback
        callbackLock.unlock()
        return token
    }
    
    func removeStatusChangeCallback(_ token: SubscriptionToken) {
        callbackLock.lock()
        statusChangeCallbacks.removeValue(forKey: token)
        callbackLock.unlock()
    }
    
    func notifyStatusChange(_ isConnected: Bool) {
        callbackLock.lock()
        let callbacks = Array(statusChangeCallbacks.values)
        callbackLock.unlock()
        
        DispatchQueue.main.async {
            callbacks.forEach { $0(isConnected) }
        }
    }
}
