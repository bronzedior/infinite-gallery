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
    
    init(imageService: ImageService = ImageService(), memoryCache: ImageCache = .shared, diskCache: DiskImageCache = .shared) {
        self.imageService = imageService
        self.memoryCache = memoryCache
        self.diskCache = diskCache
        
        NetworkMonitor.shared.onStatusChange { [weak self] isConnected in
            if isConnected {
                DispatchQueue.main.async {
                    // Retry pending requests when back online
                }
            }
        }
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
        
        diskCache.get(for: imageID) { [weak self] diskImage in
            guard let self = self else { return }
            
            if let diskImage = diskImage {
                self.memoryCache.set(diskImage, for: imageID)
                completion(index, imageID, diskImage, nil)
                return
            }
            
            if !NetworkMonitor.shared.isConnected {
                let error = NSError(domain: "NetworkMonitor", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Connection"])
                completion(index, imageID, nil, error)
                return
            }
            
            self.imageService.fetchImage(imageID: imageID, at: index, width: width, height: height) { fetchedIndex, fetchedImageID, image, error in
                if let image = image {
                    self.memoryCache.set(image, for: fetchedImageID)
                    self.diskCache.set(image, for: fetchedImageID)
                    completion(fetchedIndex, fetchedImageID, image, nil)
                } else {
                    let errorType = self.categorizeError(error)
                    let errorMessage = self.errorMessage(for: errorType)
                    let categorizedError = NSError(domain: "ImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    completion(fetchedIndex, fetchedImageID, nil, categorizedError)
                }
            }
        }
    }
    
    func cancelFetch(at index: Int) {
        imageService.cancelFetch(at: index)
    }
    
    func cancelAllFetches() {
        imageService.cancelAllFetches()
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
