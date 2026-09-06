//
//  ImageLoadingState.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 04/09/26.
//

import UIKit

enum ImageLoadingState {
    case idle
    case loading
    case success(url: String)
    case error(String)
}
