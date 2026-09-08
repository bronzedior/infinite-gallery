//
//  ImageLoadingState.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 04/09/26.
//

import UIKit

enum ImageLoadingState: Codable {
    case idle
    case loading
    case success(imageID: Int)
    case error(type: ErrorType, message: String)
    
    enum ErrorType: String, Codable {
        case noConnection, timeout, serverError, decodeFailed, unknown
    }
    
    enum Kind: String, Codable {
        case idle, loading, success, error
    }
    
    enum CodingKeys: String, CodingKey {
        case kind, imageID, type, message
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .idle:
            self = .idle
        case .loading:
            self = .loading
        case .success:
            self = .success(imageID: try container.decode(Int.self, forKey: .imageID))
        case .error:
            self = .error(
                type: try container.decode(ErrorType.self, forKey: .type),
                message: try container.decode(String.self, forKey: .message)
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .loading:
            try container.encode(Kind.loading, forKey: .kind)
        case .success(let imageID):
            try container.encode(Kind.success, forKey: .kind)
            try container.encode(imageID, forKey: .imageID)
        case .error(let type, let message):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(type, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
