//
//  ImageCell.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 04/09/26.
//

import UIKit

class ImageCell: UICollectionViewCell {
    
    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let activityIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.color = .label
        view.hidesWhenStopped = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    func setupCell() {
        contentView.backgroundColor = .systemGray6
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true
        
        contentView.addSubview(imageView)
        contentView.addSubview(activityIndicator)
        contentView.addSubview(errorLabel)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            errorLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 8),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8)
        ])
    }
    
    func updateState(_ state: ImageLoadingState) {
        imageView.image = nil
        errorLabel.text = nil

        switch state {
        case .idle:
            activityIndicator.stopAnimating()

        case .loading:
            activityIndicator.startAnimating()

        case .success(let imageID):
            if let cachedImage = ImageCache.shared.get(for: imageID) {
                imageView.image = cachedImage
            } else {
                imageView.image = UIImage(systemName: "photo.fill")?
                    .withTintColor(.systemGray3, renderingMode: .alwaysOriginal)
            }
            activityIndicator.stopAnimating()

        case .error(let message):
            errorLabel.text = "Error\n" + message
            activityIndicator.stopAnimating()
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        errorLabel.text = nil
        activityIndicator.stopAnimating()
    }
}
