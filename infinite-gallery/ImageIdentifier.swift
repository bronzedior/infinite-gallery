//
//  ImageIdentifier.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 07/09/26.
//

import Foundation

struct ImageIdentifier: Codable {
    let id: Int
    var state: ImageLoadingState
}
