//
//  ImageLoader.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 07/09/26.
//

import UIKit

class ImageLoader {
    let imageService: ImageService
    let memoryCache: ImageCache
    let diskCache: DiskImageCache
    
    final class InFlightRequest {
        let fetchIndex: Int
        var callbacks: [(index: Int, completion: (UIImage?, Error?) -> Void)]

        init(index: Int, completion: @escaping (UIImage?, Error?) -> Void) {
            fetchIndex = index
            callbacks = [(index, completion)]
        }
    }

    var inFlightRequests: [Int: InFlightRequest] = [:]
    let inFlightLock = NSLock()
    
    var onBackgroundRevalidate: ((Int, Int, UIImage) -> Void)?
    
    init(imageService: ImageService = ImageService(), memoryCache: ImageCache = .shared, diskCache: DiskImageCache = .shared) {
        self.imageService = imageService
        self.memoryCache = memoryCache
        self.diskCache = diskCache
    }
    
    func loadImage(
        imageID: Int,
        at index: Int,
        width: Int,
        height: Int,
        completion: @escaping (Int, Int, UIImage?, Error?) -> Void
    ) {
        if let memoryImage = memoryCache.get(for: imageID) {
            completion(index, imageID, memoryImage, nil)
            return
        }
        
        diskCache.get(for: imageID) { [weak self] result in
            guard let self = self else { return }
            
            guard let result = result else {
                self.fetchImageWithDeduplication(
                    imageID: imageID, at: index, width: width, height: height, completion: completion
                )
                return
            }
            
            self.memoryCache.set(result.image, for: imageID)
            completion(index, imageID, result.image, nil)
            
            if result.isStale {
                self.revalidateInBackground(imageID: imageID, at: index, width: width, height: height)
            }
        }
    }
    
    func revalidateInBackground(imageID: Int, at index: Int, width: Int, height: Int) {
        guard NetworkMonitor.shared.isConnected else { return }
        
        fetchImageWithDeduplication(
            imageID: imageID, at: index, width: width, height: height
        ) { [weak self] fetchedIndex, fetchedImageID, image, error in
            guard let self = self, let image = image else { return }
            self.onBackgroundRevalidate?(fetchedIndex, fetchedImageID, image)
        }
    }
    
    func fetchImageWithDeduplication(
        imageID: Int,
        at index: Int,
        width: Int,
        height: Int,
        completion: @escaping (Int, Int, UIImage?, Error?) -> Void
    ) {
        if !NetworkMonitor.shared.isConnected {
            let error = NSError(domain: "NetworkMonitor", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Connection"])
            completion(index, imageID, nil, error)
            return
        }
        
        inFlightLock.lock()
        
        if let request = inFlightRequests[imageID] {
            request.callbacks.append((index, { image, error in
                completion(index, imageID, image, error)
            }))
            inFlightLock.unlock()
            return
        }
        
        let request = InFlightRequest(index: index) { image, error in
            completion(index, imageID, image, error)
        }
        inFlightRequests[imageID] = request
        
        imageService.fetchImage(imageID: imageID, at: index, width: width, height: height) { [weak self] fetchedIndex, fetchedImageID, image, error in
            guard let self = self else { return }

            self.inFlightLock.lock()
            guard self.inFlightRequests[fetchedImageID] === request else {
                self.inFlightLock.unlock()
                return
            }
            self.inFlightRequests.removeValue(forKey: fetchedImageID)
            let callbacks = request.callbacks
            self.inFlightLock.unlock()
            
            let result: (image: UIImage?, error: Error?)
            if let image = image {
                self.memoryCache.set(image, for: fetchedImageID)
                self.diskCache.set(image, for: fetchedImageID)
                result = (image, nil)
            } else if let error = error as? URLError, error.code == .cancelled {
                result = (nil, error)
            } else {
                let errorType = self.categorizeError(error)
                let message = self.errorMessage(for: errorType)
                let categorizedError = NSError(domain: "ImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
                result = (nil, categorizedError)
            }
            
            callbacks.forEach { callback in
                callback.completion(result.image, result.error)
            }
        }
        inFlightLock.unlock()
    }
    
    func cancelFetch(at index: Int) {
        inFlightLock.lock()
        var callbacks: [(UIImage?, Error?) -> Void] = []
        for (imageID, request) in inFlightRequests {
            callbacks += request.callbacks.filter { $0.index == index }.map(\.completion)
            request.callbacks.removeAll { $0.index == index }
            if request.callbacks.isEmpty {
                inFlightRequests.removeValue(forKey: imageID)
                imageService.cancelFetch(at: request.fetchIndex)
            }
        }
        inFlightLock.unlock()
        notifyCancellation(callbacks)
    }
    
    func cancelAllFetches() {
        inFlightLock.lock()
        let callbacks = inFlightRequests.values.flatMap { $0.callbacks.map(\.completion) }
        inFlightRequests.removeAll()
        imageService.cancelAllFetches()
        inFlightLock.unlock()
        notifyCancellation(callbacks)
    }

    private func notifyCancellation(_ callbacks: [(UIImage?, Error?) -> Void]) {
        DispatchQueue.main.async {
            callbacks.forEach { $0(nil, URLError(.cancelled)) }
        }
    }
    
    func categorizeError(_ error: Error?) -> ImageLoadingState.ErrorType {
        guard let error = error as NSError? else { return .unknown }
        
        if error.domain == "NetworkMonitor" {
            return .noConnection
        }
        
        switch error.code {
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .noConnection
        default:
            return .unknown
        }
    }
    
    func errorMessage(for type: ImageLoadingState.ErrorType) -> String {
        switch type {
        case .noConnection:
            return "No Connection"
        case .timeout:
            return "Connection Timeout"
        case .serverError:
            return "Server Error"
        case .decodeFailed:
            return "Failed to load"
        case .unknown:
            return "Failed to load"
        }
    }
}
