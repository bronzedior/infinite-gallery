import XCTest
import UIKit
@testable import infinite_gallery

final class ImageResponseStub: URLProtocol {
    static let lock = NSLock()
    static var response: (status: Int, data: Data, error: Error?) = (200, imageData, nil)
    static var requests: [URL] = []
    static let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

    static func reset(status: Int = 200, data: Data = imageData, error: Error? = nil) {
        lock.lock()
        response = (status, data, error)
        requests = []
        lock.unlock()
    }

    static var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "picsum.photos" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let response = Self.response
        Self.requests.append(request.url!)
        Self.lock.unlock()
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: response.status,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor
final class TestViewController: ViewController {
    override func persistSession() {}
    override func loadInitialImages() {}
}

@MainActor
class ImagePipelineTests: XCTestCase {
    var directory: URL!
    var loader: ImageLoader!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(ImageResponseStub.self)
        ImageResponseStub.reset()
        NetworkMonitor.shared.monitor.cancel()
        NetworkMonitor.shared.lock.lock()
        NetworkMonitor.shared._isConnected = true
        NetworkMonitor.shared.lock.unlock()
        CircuitBreaker.shared.recordSuccess()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        loader = ImageLoader(memoryCache: ImageCache(), diskCache: DiskImageCache(directoryURL: directory))
    }

    override func tearDown() {
        loader.cancelAllFetches()
        loader.diskCache.ioQueue.sync {}
        try? FileManager.default.removeItem(at: directory)
        URLProtocol.unregisterClass(ImageResponseStub.self)
        super.tearDown()
    }

    func until(_ message: String, timeout: TimeInterval = 3, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        XCTAssertTrue(condition(), message)
    }

    func operation(at index: Int) -> ImageFetchOperation? {
        loader.imageService.lock.lock()
        defer { loader.imageService.lock.unlock() }
        return loader.imageService.operations[index]
    }

    func testHTTPAndDecodeFailuresReachCellWithCorrectCategory() {
        for (status, data, expected) in [(503, ImageResponseStub.imageData, ImageLoadingState.ErrorType.serverError),
                                       (200, Data("invalid image".utf8), .decodeFailed),
                                       (404, ImageResponseStub.imageData, .serverError)] {
            ImageResponseStub.reset(status: status, data: data)
            CircuitBreaker.shared.recordSuccess()
            let done = expectation(description: "HTTP \(status)")
            loader.loadImage(imageID: status, at: 0, width: 1, height: 1) { _, _, image, error in
                XCTAssertNil(image)
                let type = ImageLoadingState.ErrorType.categorize(error)
                XCTAssertEqual(type, expected)
                let cell = ImageCell(frame: .zero)
                cell.updateState(.error(type: type, message: type.message))
                XCTAssertEqual(cell.errorLabel.text, "Error\n" + expected.message)
                XCTAssertFalse(cell.activityIndicator.isAnimating)
                done.fulfill()
            }
            wait(for: [done], timeout: 12)
        }
    }

    func testDifferentPixelSizesUseDifferentNetworkAndCacheEntries() throws {
        for (iteration, size) in [1, 2, 1, 2].enumerated() {
            if iteration == 2 {
                loader.diskCache.ioQueue.sync {}
                loader.memoryCache.removeAll()
            }
            let done = expectation(description: "size \(size)")
            loader.loadImage(imageID: 99, at: 0, width: size, height: size) { _, _, image, error in
                XCTAssertNotNil(image)
                XCTAssertNil(error)
                done.fulfill()
            }
            wait(for: [done], timeout: 3)
        }
        XCTAssertEqual(ImageResponseStub.requestedURLs.map(\.path), ["/seed/99/1/1", "/seed/99/2/2"])
        loader.diskCache.ioQueue.sync {}
        for size in [1, 2] {
            let key = ImageRequestKey(imageID: 99, width: size, height: size)
            XCTAssertEqual(try Data(contentsOf: loader.diskCache.fileURL(for: key)), ImageResponseStub.imageData)
            XCTAssertNotNil(loader.memoryCache.get(for: key))
        }
    }

    func testCancelDuringDiskLookupCannotStartAnObsoleteNetworkRequest() {
        let cancelled = expectation(description: "cancelled disk lookup")
        loader.loadImage(imageID: 99, at: 0, width: 1, height: 1) { _, _, image, error in
            XCTAssertNil(image)
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
            cancelled.fulfill()
        }
        loader.cancelFetch(at: 0)
        let replacement = expectation(description: "replacement")
        loader.loadImage(imageID: 99, at: 0, width: 2, height: 2) { _, _, image, error in
            XCTAssertNotNil(image)
            XCTAssertNil(error)
            replacement.fulfill()
        }
        wait(for: [cancelled, replacement], timeout: 3)
        XCTAssertEqual(ImageResponseStub.requestedURLs.map(\.path), ["/seed/99/2/2"])
        XCTAssertTrue(loader.inFlightRequests.isEmpty)
    }

    func testSharedRequestSurvivesUntilLastSubscriberCancels() {
        ImageResponseStub.reset(error: URLError(.networkConnectionLost))
        let cancelled = expectation(description: "both cancelled")
        cancelled.expectedFulfillmentCount = 2
        for index in 0..<2 {
            loader.loadImage(imageID: 98, at: index, width: 1, height: 1) { _, _, _, error in
                XCTAssertEqual((error as? URLError)?.code, .cancelled)
                cancelled.fulfill()
            }
        }
        until("Request enters retry") {
            guard let op = self.operation(at: 0) else { return false }
            op.retryLock.lock()
            defer { op.retryLock.unlock() }
            return op.pendingRetryWorkItem != nil
        }
        let operation = operation(at: 0)!
        loader.cancelFetch(at: 0)
        XCTAssertFalse(operation.isCancelled)
        loader.cancelFetch(at: 1)
        XCTAssertTrue(operation.isFinished)
        XCTAssertTrue(loader.inFlightRequests.isEmpty)
        ImageResponseStub.reset()
        let reloaded = expectation(description: "reload same image")
        loader.loadImage(imageID: 98, at: 0, width: 1, height: 1) { _, _, image, error in
            XCTAssertNotNil(image)
            XCTAssertNil(error)
            reloaded.fulfill()
        }
        wait(for: [cancelled, reloaded], timeout: 3)
        XCTAssertTrue(loader.inFlightRequests.isEmpty)
    }

    func testCancellingReconnectWaitFinishesAndRemovesSubscription() {
        NetworkMonitor.shared.lock.lock()
        NetworkMonitor.shared._isConnected = false
        NetworkMonitor.shared.lock.unlock()
        ImageResponseStub.reset(error: URLError(.networkConnectionLost))
        let operation = ImageFetchOperation(index: 0, imageID: 97,
            url: URL(string: "https://picsum.photos/seed/97/1/1")!)
        let cancelled = expectation(description: "reconnect cancelled")
        XCTAssertTrue(operation.addCompletion { _, _, _, _, error in
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
            cancelled.fulfill()
        })
        let queue = OperationQueue()
        queue.addOperation(operation)
        until("Waiting for reconnect") {
            operation.retryLock.lock()
            defer { operation.retryLock.unlock() }
            return operation.reconnectToken != nil
        }
        operation.retryLock.lock()
        let token = operation.reconnectToken
        operation.retryLock.unlock()
        operation.cancel()
        wait(for: [cancelled], timeout: 2)
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isExecuting)
        NetworkMonitor.shared.callbackLock.lock()
        let remains = token.map { NetworkMonitor.shared.statusChangeCallbacks[$0] != nil } ?? false
        NetworkMonitor.shared.callbackLock.unlock()
        XCTAssertFalse(remains)
    }

    func testOfflineAndInvalidDimensionsReturnConsistentErrors() {
        NetworkMonitor.shared.lock.lock()
        NetworkMonitor.shared._isConnected = false
        NetworkMonitor.shared.lock.unlock()
        let offline = expectation(description: "offline")
        loader.loadImage(imageID: 88, at: 0, width: 1, height: 1) { _, _, _, error in
            XCTAssertEqual(ImageLoadingState.ErrorType.categorize(error), .noConnection)
            offline.fulfill()
        }
        wait(for: [offline], timeout: 2)
        NetworkMonitor.shared.lock.lock()
        NetworkMonitor.shared._isConnected = true
        NetworkMonitor.shared.lock.unlock()
        let invalid = expectation(description: "invalid size")
        loader.loadImage(imageID: 88, at: 0, width: 0, height: 1) { _, _, _, error in
            XCTAssertEqual((error as? URLError)?.code, .badURL)
            invalid.fulfill()
        }
        wait(for: [invalid], timeout: 2)
        XCTAssertTrue(loader.inFlightRequests.isEmpty)
        XCTAssertTrue(ImageResponseStub.requestedURLs.isEmpty)
    }

    func testFourCancelledBackoffsFreeQueueSlots() {
        for cancelAll in [false, true] {
            ImageResponseStub.reset(error: URLError(.networkConnectionLost))
            let cancelled = expectation(description: "four cancelled")
            cancelled.expectedFulfillmentCount = 4
            for index in 0..<4 {
                loader.loadImage(imageID: index, at: index, width: 1, height: 1) { _, _, _, error in
                    XCTAssertEqual((error as? URLError)?.code, .cancelled)
                    cancelled.fulfill()
                }
            }
            until("Four requests enter retry") {
                self.loader.imageService.lock.lock()
                let operations = Array(self.loader.imageService.operations.values)
                self.loader.imageService.lock.unlock()
                return operations.count == 4 && operations.allSatisfy { op in
                    op.retryLock.lock()
                    defer { op.retryLock.unlock() }
                    return op.pendingRetryWorkItem != nil
                }
            }
            if cancelAll { loader.cancelAllFetches() }
            else { for index in 0..<4 { loader.cancelFetch(at: index) } }
            ImageResponseStub.reset()
            let loaded = expectation(description: "queue continues")
            loader.loadImage(imageID: 99, at: 99, width: 1, height: 1) { _, _, image, error in
                XCTAssertNotNil(image)
                XCTAssertNil(error)
                loaded.fulfill()
            }
            wait(for: [cancelled, loaded], timeout: 3)
            loader.memoryCache.removeAll()
        }
    }

    func testViewControllerRequestsRetinaPixelsAndReloadsAfterRotation() {
        let controller = TestViewController(imageLoader: loader)
        controller.loadViewIfNeeded()
        controller.traitOverrides.displayScale = 3
        controller.currentScreenSize = CGSize(width: 100, height: 200)
        controller.imageIdentifiers = [ImageIdentifier(id: Int.random(in: Int.min..<0), state: .idle)]
        controller.collectionView.reloadData()
        controller.fetchImage(at: 0)
        until("Portrait image loaded") {
            if case .success = controller.imageIdentifiers[0].state { return true }
            return false
        }
        XCTAssertTrue(ImageResponseStub.requestedURLs.last!.path.hasSuffix("/300/600"))
        controller.didLoadInitialImages = true
        controller.view.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        controller.viewDidLayoutSubviews()
        // Layout may have no visible cells in a test window; request the newly sized cell explicitly.
        controller.fetchImage(at: 0)
        until("Landscape image loaded") {
            if case .success = controller.imageIdentifiers[0].state { return true }
            return false
        }
        XCTAssertTrue(ImageResponseStub.requestedURLs.last!.path.hasSuffix("/1704/600"))
        let cell = ImageCell(frame: .zero)
        let image = loader.memoryCache.get(for: controller.imageKey(for: 0))
        cell.updateState(controller.imageIdentifiers[0].state, image: image)
        XCTAssertNotNil(image)
        XCTAssertTrue(cell.imageView.image === image)
        XCTAssertFalse(cell.activityIndicator.isAnimating)
        controller.imageLoader.cancelAllFetches()
    }
}
