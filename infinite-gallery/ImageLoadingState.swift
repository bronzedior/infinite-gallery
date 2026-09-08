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
    case success(imageID: Int)
    case error(type: ErrorType, message: String)
    
    enum ErrorType {
        case noConnection
        case timeout
        case serverError
        case decodeFailed
        case unknown
    }
}
