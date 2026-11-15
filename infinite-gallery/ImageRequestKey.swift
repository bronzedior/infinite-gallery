import Foundation

struct ImageRequestKey: Hashable {
    let imageID: Int
    let width: Int
    let height: Int

    var cacheKey: String { "\(imageID)_\(width)x\(height)" }
}
