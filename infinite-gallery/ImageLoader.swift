import UIKit

class ImageLoader {
    let imageService: ImageService
    let memoryCache: ImageCache
    let diskCache: DiskImageCache

    final class InFlightRequest {
        let fetchIndex: Int
        var operation: ImageFetchOperation?
        var callbacks: [(index: Int, completion: (UIImage?, Error?) -> Void)]

        init(index: Int, completion: @escaping (UIImage?, Error?) -> Void) {
            fetchIndex = index
            callbacks = [(index, completion)]
        }
    }

    var inFlightRequests: [ImageRequestKey: InFlightRequest] = [:]
    let inFlightLock = NSLock()
    var onBackgroundRevalidate: ((Int, Int, UIImage) -> Void)?

    init(imageService: ImageService = ImageService(), memoryCache: ImageCache = .shared, diskCache: DiskImageCache = .shared) {
        self.imageService = imageService
        self.memoryCache = memoryCache
        self.diskCache = diskCache
    }

    func loadImage(imageID: Int, at index: Int, width: Int, height: Int,
                   completion: @escaping (Int, Int, UIImage?, Error?) -> Void) {
        let key = ImageRequestKey(imageID: imageID, width: width, height: height)
        if let image = memoryCache.get(for: key) {
            completion(index, imageID, image, nil)
            return
        }
        requestImage(key: key, at: index, readDiskCache: true, completion: completion)
    }

    func revalidateInBackground(imageID: Int, at index: Int, width: Int, height: Int) {
        guard NetworkMonitor.shared.isConnected else { return }
        let key = ImageRequestKey(imageID: imageID, width: width, height: height)
        requestImage(key: key, at: index, readDiskCache: false) { [weak self] index, imageID, image, _ in
            guard let image else { return }
            self?.onBackgroundRevalidate?(index, imageID, image)
        }
    }

    private func requestImage(key: ImageRequestKey, at index: Int, readDiskCache: Bool,
                              completion: @escaping (Int, Int, UIImage?, Error?) -> Void) {
        inFlightLock.lock()
        if let request = inFlightRequests[key] {
            request.callbacks.append((index, { completion(index, key.imageID, $0, $1) }))
            inFlightLock.unlock()
            return
        }
        let request = InFlightRequest(index: index) { completion(index, key.imageID, $0, $1) }
        inFlightRequests[key] = request
        inFlightLock.unlock()

        if readDiskCache {
            diskCache.get(for: key) { [weak self] result in
                guard let self else { return }
                if let result {
                    let delivered = self.complete(request, key: key, image: result.image, data: nil, error: nil)
                    if delivered && result.isStale {
                        self.revalidateInBackground(imageID: key.imageID, at: index, width: key.width, height: key.height)
                    }
                } else {
                    self.startFetch(request, key: key)
                }
            }
        } else {
            startFetch(request, key: key)
        }
    }

    private func startFetch(_ request: InFlightRequest, key: ImageRequestKey) {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        guard inFlightRequests[key] === request else { return }
        request.operation = imageService.fetchImage(imageID: key.imageID, at: request.fetchIndex,
            width: key.width, height: key.height) { [weak self] _, _, image, data, error in
                self?.complete(request, key: key, image: image, data: data, error: error)
            }
    }

    @discardableResult
    private func complete(_ request: InFlightRequest, key: ImageRequestKey, image: UIImage?, data: Data?, error: Error?) -> Bool {
        inFlightLock.lock()
        guard inFlightRequests[key] === request else {
            inFlightLock.unlock()
            return false
        }
        inFlightRequests.removeValue(forKey: key)
        let callbacks = request.callbacks
        inFlightLock.unlock()
        if let image {
            memoryCache.set(image, for: key)
            if let data { diskCache.set(data, for: key) }
        }
        callbacks.forEach { $0.completion(image, error) }
        return true
    }

    func cancelFetch(at index: Int) {
        inFlightLock.lock()
        var callbacks: [(UIImage?, Error?) -> Void] = []
        for (key, request) in inFlightRequests {
            callbacks += request.callbacks.filter { $0.index == index }.map(\.completion)
            request.callbacks.removeAll { $0.index == index }
            if request.callbacks.isEmpty {
                inFlightRequests.removeValue(forKey: key)
                request.operation?.cancel()
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
}
