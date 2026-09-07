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

            self.imageService.fetchImage(imageID: imageID, at: index, width: width, height: height) { fetchedIndex, fetchedImageID, image, error in
                if let image = image {
                    self.memoryCache.set(image, for: fetchedImageID)
                    self.diskCache.set(image, for: fetchedImageID)
                }
                completion(fetchedIndex, fetchedImageID, image, error)
            }
        }
    }

    func cancelFetch(at index: Int) {
        imageService.cancelFetch(at: index)
    }

    func cancelAllFetches() {
        imageService.cancelAllFetches()
    }
}
