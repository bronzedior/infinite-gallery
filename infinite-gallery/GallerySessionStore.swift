//
//  GallerySessionStore.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 08/09/26.
//

import Foundation

class GallerySessionStore {
    static let shared = GallerySessionStore()

    let fileURL: URL
    let ioQueue = DispatchQueue(label: "com.infinite-gallery.gallerysessionstore", qos: .utility)

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("gallery_session.json")
    }

    func save(_ identifiers: [ImageIdentifier]) {
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(identifiers) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }

    func load(completion: @escaping ([ImageIdentifier]?) -> Void) {
        ioQueue.async {
            guard let data = FileManager.default.contents(atPath: self.fileURL.path),
                  let identifiers = try? JSONDecoder().decode([ImageIdentifier].self, from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(identifiers) }
        }
    }
}
