import XCTest
import UIKit
@testable import infinite_gallery

final class HeldFetchOperation: ImageFetchOperation, @unchecked Sendable {
    override func attemptFetch(attempt: Int) {}
}

@MainActor
final class CacheAndRetryTests: XCTestCase {
    func testErrorCategoriesAndMessagesHaveOneSource() {
        let type = ImageLoadingState.ErrorType.self
        XCTAssertEqual(type.categorize(URLError(.timedOut)), .timeout)
        XCTAssertEqual(type.categorize(URLError(.notConnectedToInternet)), .noConnection)
        XCTAssertEqual(type.categorize(URLError(.networkConnectionLost)), .noConnection)
        XCTAssertEqual(type.categorize(ImageLoadingState.ErrorType.serverError), .serverError)
        XCTAssertEqual(type.categorize(ImageLoadingState.ErrorType.decodeFailed), .decodeFailed)
        XCTAssertEqual(type.categorize(nil), .unknown)
        XCTAssertEqual(ImageLoadingState.ErrorType.noConnection.localizedDescription, "No Connection")
    }

    func testBackoffJitterCapAndRetryPolicy() {
        let operation = ImageFetchOperation(index: 0, imageID: 1, url: URL(string: "https://picsum.photos/seed/1/1/1")!)
        for index in 0..<4 {
            let base = 0.5 * pow(2, Double(index))
            for _ in 0..<100 {
                let delay = operation.calculateBackoffDelay(for: index)
                XCTAssertGreaterThanOrEqual(delay, base * 0.8)
                XCTAssertLessThanOrEqual(delay, base * 1.2)
            }
        }
        XCTAssertEqual(operation.calculateBackoffDelay(for: 1000), 8)
        CircuitBreaker.shared.recordSuccess()
        let response = HTTPURLResponse(url: operation.url, statusCode: 503, httpVersion: nil, headerFields: nil)
        XCTAssertTrue(operation.shouldRetry(error: nil, response: response, attempt: 0))
        XCTAssertFalse(operation.shouldRetry(error: nil, response: response, attempt: operation.maxAttempts))
        let missing = HTTPURLResponse(url: operation.url, statusCode: 404, httpVersion: nil, headerFields: nil)
        XCTAssertFalse(operation.shouldRetry(error: nil, response: missing, attempt: 0))
        XCTAssertFalse(operation.shouldRetry(error: URLError(.cancelled), response: nil, attempt: 0))
        XCTAssertTrue(operation.shouldRetry(error: URLError(.networkConnectionLost), response: nil, attempt: 0))
    }

    func testCircuitBreakerRecoveryFailureAndProbeTimeout() {
        let breaker = CircuitBreaker()
        for _ in 0..<breaker.failureThreshold { breaker.recordFailure() }
        XCTAssertTrue(breaker.isOpen)
        XCTAssertFalse(breaker.canProceed())
        breaker.openedAt = Date().addingTimeInterval(-breaker.currentOpenDuration - 1)
        XCTAssertTrue(breaker.canProceed())
        XCTAssertFalse(breaker.canProceed())
        breaker.recordFailure()
        XCTAssertEqual(breaker.currentOpenDuration, 30)
        breaker.openedAt = Date().addingTimeInterval(-31)
        XCTAssertTrue(breaker.canProceed())
        breaker.halfOpenStartedAt = Date().addingTimeInterval(-breaker.halfOpenTimeout - 1)
        XCTAssertFalse(breaker.canProceed())
        XCTAssertEqual(breaker.currentOpenDuration, 60)
        let recovered = expectation(description: "recovery notification")
        let token = breaker.onRecover { recovered.fulfill() }
        breaker.recordSuccess()
        XCTAssertTrue(breaker.canProceed())
        XCTAssertFalse(breaker.isOpen)
        XCTAssertEqual(breaker.currentOpenDuration, breaker.baseOpenDuration)
        wait(for: [recovered], timeout: 1)
        breaker.removeRecoveryCallback(token)
    }

    func testConcurrentStartCancelAndFinishOnlyNotifyOnce() {
        let callbacks = expectation(description: "one callback per operation")
        callbacks.expectedFulfillmentCount = 100
        for _ in 0..<100 {
            let operation = HeldFetchOperation(index: 0, imageID: 1, url: URL(string: "https://picsum.photos/seed/1/1/1")!)
            XCTAssertTrue(operation.addCompletion { _, _, _, _, error in
                XCTAssertEqual((error as? URLError)?.code, .cancelled)
                callbacks.fulfill()
            })
            let lock = NSLock()
            var notifications = 0
            let observation = operation.observe(\.isFinished) { _, _ in
                lock.lock()
                notifications += 1
                lock.unlock()
            }
            DispatchQueue.concurrentPerform(iterations: 3) { index in
                switch index {
                case 0: operation.start()
                case 1: operation.cancel()
                default: operation.finish()
                }
            }
            operation.cancel()
            XCTAssertTrue(operation.isFinished)
            XCTAssertFalse(operation.isExecuting)
            XCTAssertEqual(notifications, 1)
            withExtendedLifetime(observation) {}
        }
        wait(for: [callbacks], timeout: 3)
    }

    func testDiskBudgetEvictsOldestAndSkipsOversizedData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = ImageResponseStub.imageData
        let cache = DiskImageCache(directoryURL: directory, maxBytes: data.count * 2)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ImageRequestKey(imageID: 1, width: 1, height: 1)
        cache.set(data, for: first)
        cache.ioQueue.sync {}
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: cache.fileURL(for: first).path)
        for id in 2...3 { cache.set(data, for: ImageRequestKey(imageID: id, width: 1, height: 1)) }
        let oversized = ImageRequestKey(imageID: 4, width: 1, height: 1)
        cache.set(Data(count: data.count * 3), for: oversized)
        cache.ioQueue.sync {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL(for: first).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL(for: oversized).path))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let total = try files.reduce(0) { try $0 + $1.resourceValues(forKeys: [.fileSizeKey]).fileSize! }
        XCTAssertEqual(total, data.count * 2)
        let last = ImageRequestKey(imageID: 3, width: 1, height: 1)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: cache.fileURL(for: last).path)
        let hit = expectation(description: "cache hit")
        cache.get(for: last) { result in
            XCTAssertNotNil(result?.image)
            XCTAssertEqual(result?.isStale, true)
            hit.fulfill()
        }
        await fulfillment(of: [hit], timeout: 10)
    }

    func testDiskBudgetIsEnforcedOnStartupIncludingLegacyFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("123.jpg")
        try ImageResponseStub.imageData.write(to: legacy)
        let cache = DiskImageCache(directoryURL: directory, maxBytes: 0)
        cache.ioQueue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
