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
    var imageStates: [ImageLoadingState] = []
    let imageService = ImageService()
    var isLoadingMore = false
    var currentScreenSize: CGSize = .zero
    
    let visibleCacheRange = 5
    var lastLoadedRange: ClosedRange<Int>? = nil
    
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
        loadInitialImages()
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
        imageStates = Array(repeating: .idle, count: 5)
        collectionView.reloadData()
        
        for index in 0..<5 {
            fetchImage(at: index)
        }
    }
    
    func fetchImage(at index: Int) {
        guard index < imageStates.count else { return }
        
        imageStates[index] = .loading
        collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        
        let width = Int(currentScreenSize.width)
        let height = Int(currentScreenSize.height)
        
        imageService.fetchImage(at: index, width: width, height: height) { [weak self] fetchedIndex, image, error in
            guard let self = self, fetchedIndex < self.imageStates.count else { return }
            
            if let image = image {
                ImageCache.shared.set(image, for: fetchedIndex)
                self.imageStates[fetchedIndex] = .success(url: "img_\(fetchedIndex)")
            } else {
                self.imageStates[fetchedIndex] = .error("Failed to load")
            }
            
            self.collectionView.reloadItems(at: [IndexPath(item: fetchedIndex, section: 0)])
        }
    }
    
    func loadMoreImages() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        
        let currentCount = imageStates.count
        let newCount = currentCount + 5
        
        imageStates.append(contentsOf: Array(repeating: ImageLoadingState.idle, count: 5))
        
        var indexPaths: [IndexPath] = []
        for i in currentCount..<newCount {
            indexPaths.append(IndexPath(item: i, section: 0))
        }
        
        collectionView.performBatchUpdates({
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
        
        let shouldLoadRange = (max(0, minVisible - visibleCacheRange)...min(imageStates.count - 1, maxVisible + visibleCacheRange))
        
        for i in shouldLoadRange {
            if case .idle = imageStates[i] {
                fetchImage(at: i)
            }
        }
        
        if let lastRange = lastLoadedRange {
            let toUnload = lastRange.filter { !shouldLoadRange.contains($0) }
            for i in toUnload {
                ImageCache.shared.remove(for: i)
            }
        }
        
        lastLoadedRange = shouldLoadRange
    }
    
    deinit {
        imageService.cancelAllFetches()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ImageCache.shared.removeAll()
    }
}

extension ViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageStates.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageCell", for: indexPath) as! ImageCell
        cell.updateState(imageStates[indexPath.item])
        return cell
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
