//
//  ViewController.swift
//  infinite-gallery
//
//  Created by Fransiscus Bronzedior Driandonny Noryon on 03/09/26.
//

import UIKit

class ViewController: UIViewController {
    
    let headerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        return view
    }()
    
    let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Infinite Gallery"
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textAlignment = .center
        return label
    }()
    
    let dividerLine: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        return view
    }()
    
    let collectionView: UICollectionView
    var imageIdentifiers: [ImageIdentifier] = []
    let imageLoader = ImageLoader()
    var isLoadingMore = false
    var currentScreenSize: CGSize = .zero
    
    let visibleCacheRange = 5
    var lastLoadedRange: ClosedRange<Int>? = nil
    
    var didLoadInitialImages = false
    
    var reconnectToken: NetworkMonitor.SubscriptionToken?
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 0
        layout.itemSize = .zero
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemGray6
        
        setupHeader()
        setupCollectionView()
        subscribeToNetworkReconnect()
        //        loadInitialImages()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let size = view.bounds.size
        let padding: CGFloat = 32
        let newItemSize = CGSize(width: size.width - padding, height: size.height - 200)
        
        if newItemSize != currentScreenSize {
            currentScreenSize = newItemSize
            if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
                layout.itemSize = newItemSize
                layout.invalidateLayout()
            }
            
            if !didLoadInitialImages, newItemSize.width > 0, newItemSize.height > 0 {
                didLoadInitialImages = true
                loadInitialImages()
            }
        }
    }
    
    func setupHeader() {
        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        view.addSubview(dividerLine)
        
        [headerView, titleLabel, dividerLine].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: dividerLine.topAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: headerView.safeAreaLayoutGuide.topAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -16),
            
            dividerLine.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dividerLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dividerLine.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    func setupCollectionView() {
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.delegate = self
        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: "ImageCell")
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .systemGray6
        
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: dividerLine.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    func loadInitialImages() {
        imageIdentifiers = (0..<5).map { _ in ImageIdentifier(id: Int.random(in: 1...1_000_000), state: .idle) }
        collectionView.reloadData()
        
        for index in 0..<5 {
            fetchImage(at: index)
        }
    }
    
    func fetchImage(at index: Int) {
        guard index < imageIdentifiers.count else { return }
        guard currentScreenSize.width > 0, currentScreenSize.height > 0 else { return }
        
        let imageID = imageIdentifiers[index].id
        imageIdentifiers[index].state = .loading
        collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        
        let width = Int(currentScreenSize.width)
        let height = Int(currentScreenSize.height)
        
        imageLoader.loadImage(imageID: imageID, at: index, width: width, height: height) { [weak self] fetchedIndex, fetchedImageID, image, error in
            guard let self = self, fetchedIndex < self.imageIdentifiers.count else { return }
            guard self.imageIdentifiers[fetchedIndex].id == fetchedImageID else { return }
            
            if let image = image {
                self.imageIdentifiers[fetchedIndex].state = .success(imageID: fetchedImageID)
            } else if let error = error as NSError? {
                let errorType = self.categorizeError(error)
                let message = error.userInfo[NSLocalizedDescriptionKey] as? String ?? "Failed to load"
                self.imageIdentifiers[fetchedIndex].state = .error(type: errorType, message: message)
            } else {
                self.imageIdentifiers[fetchedIndex].state = .error(type: .unknown, message: "Failed to load")
            }
            
            self.collectionView.reloadItems(at: [IndexPath(item: fetchedIndex, section: 0)])
        }
    }
    
    func loadMoreImages() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        let currentCount = imageIdentifiers.count
        let newCount = currentCount + 5
        
        var indexPaths: [IndexPath] = []
        for i in currentCount..<newCount {
            indexPaths.append(IndexPath(item: i, section: 0))
        }
        
        collectionView.performBatchUpdates({
            self.imageIdentifiers.append(contentsOf: (0..<5).map { _ in ImageIdentifier(id: Int.random(in: 1...1_000_000), state: .idle) })
            self.collectionView.insertItems(at: indexPaths)
        }) { _ in
            for i in currentCount..<newCount {
                self.fetchImage(at: i)
            }
            self.isLoadingMore = false
        }
    }
    
    func updateImageCache() {
        let visibleIndices = collectionView.indexPathsForVisibleItems.map { $0.item }
        guard !visibleIndices.isEmpty else { return }
        
        let minVisible = visibleIndices.min()!
        let maxVisible = visibleIndices.max()!
        
        let shouldLoadRange = (max(0, minVisible - visibleCacheRange)...min(imageIdentifiers.count - 1, maxVisible + visibleCacheRange))
        
        for i in shouldLoadRange {
            if case .idle = imageIdentifiers[i].state {
                fetchImage(at: i)
            }
        }
        
        if let lastRange = lastLoadedRange {
            let toUnload = lastRange.filter { !shouldLoadRange.contains($0) }
            for i in toUnload {
                ImageCache.shared.remove(for: imageIdentifiers[i].id)
                // TODO: Further Investigation
                // Setiap user scroll up akan re-fetch data
                // Pertimbangan memory/cpu usage nya seperti apa
                if case .success = imageIdentifiers[i].state {
                    imageIdentifiers[i].state = .idle
                }
            }
        }
        
        lastLoadedRange = shouldLoadRange
    }
    
    func categorizeError(_ error: NSError) -> ImageLoadingState.ErrorType {
        if error.domain == "NetworkMonitor" {
            return .noConnection
        }
        
        switch error.code {
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .noConnection
        default:
            return .unknown
        }
    }
    
    deinit {
        imageLoader.cancelAllFetches()
        if let token = reconnectToken {
            NetworkMonitor.shared.removeStatusChangeCallback(token)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // TODO: Further Investigation
        // Setiap user scroll ke image ke-N dan keluar dari app
        // Ketika membuka app kembali dan scroll up
        // Image tidak berhasil ke fetch / re-fetch
        // ImageCache.shared.removeAll()
    }
    
    func subscribeToNetworkReconnect() {
        reconnectToken = NetworkMonitor.shared.onStatusChange { [weak self] isConnected in
            guard let self = self, isConnected else { return }
            self.retryFailedImages()
        }
    }
    
    func retryFailedImages() {
        let visibleIndices = collectionView.indexPathsForVisibleItems.map { $0.item }
        guard !visibleIndices.isEmpty else { return }
        let minVisible = visibleIndices.min()!
        let maxVisible = visibleIndices.max()!
        let range = max(0, minVisible - visibleCacheRange)...min(imageIdentifiers.count - 1, maxVisible + visibleCacheRange)
        
        for index in range where index < imageIdentifiers.count {
            if case .error = imageIdentifiers[index].state {
                imageIdentifiers[index].state = .idle
                fetchImage(at: index)
            }
        }
    }
}

extension ViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageIdentifiers.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageCell", for: indexPath) as! ImageCell
        cell.updateState(imageIdentifiers[indexPath.item].state)
        return cell
    }
}

extension ViewController: UICollectionViewDataSourcePrefetching {
    
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let index = indexPath.item
            guard index < imageIdentifiers.count else { continue }
            if case .idle = imageIdentifiers[index].state {
                fetchImage(at: index)
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let index = indexPath.item
            guard index < imageIdentifiers.count else { continue }
            imageLoader.cancelFetch(at: index)
            if case .loading = imageIdentifiers[index].state {
                imageIdentifiers[index].state = .idle
            }
        }
    }
}

extension ViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateImageCache()
        
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let screenHeight = scrollView.frame.height
        
        if offsetY + screenHeight >= contentHeight - screenHeight {
            loadMoreImages()
        }
    }
}

//#Preview {
//    ViewController()
//}
