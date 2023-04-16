//
//  GalleryViewController.swift
//  Gallery
//
//  Created by Alex on 16.02.2021.
//

import UIKit
import SwiftyJSON

protocol GalleryViewInput: class {
    func show(message: String)
    func didAppendData()
    func didUpdateData()
    func didUpdateIndex(index: Int, total: Int)
    func loadingStart()
    func loadingFinish()
}

final class GalleryViewController: UIViewController {
    
    //MARK: - IBOutlets
    
    @IBOutlet weak var searchBar: UISearchBar! {
        didSet {
            searchBar.delegate = self
            searchBar.placeholder = "enter search text"
            searchBar.isHidden = true
        }
    }
    
    @IBOutlet weak var collectionView: UICollectionView! {
        didSet {
            collectionView.collectionViewLayout = getLayout()
            let cellNibName = String(describing: GalleryCell.self)
            collectionView.register(UINib(nibName: cellNibName, bundle: nil), forCellWithReuseIdentifier: cellNibName)
            collectionView.delegate = self
        }
    }
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView! {
        didSet {
            activityIndicator.hidesWhenStopped = true
        }
    }
    
    @IBOutlet weak var imageView: UIImageView! {
        didSet{
            imageView.isHidden = false
        }
    }
    
    //MARK: - Properties
    
    var presenter: GalleryViewOutput!
    var collectionDataSource: UICollectionViewDiffableDataSource<Section, UIImage>!
    
    var loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "loading image..."
        label.textAlignment = .center
        label.textColor = .black
        label.isHidden = false
        label.sizeToFit()
        return label
    }()
       
    var isLoading: Bool = false {
        didSet {
            loadingLabel.isHidden = !isLoading
        }
    }
       
    var loadingMessage: String = "" {
        didSet {
            loadingLabel.text = "building index " + loadingMessage
        }
    }
    
    //MARK: - LiceCycles
    
    deinit {
        print("GalleryViewController deinit")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("GalleryViewController init")
        createDataSource()
        presenter.viewDidLoad()
        collectionView.addSubview(loadingLabel)
        collectionView.clipsToBounds = true
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            loadingLabel.widthAnchor.constraint(equalToConstant: 300),
            loadingLabel.heightAnchor.constraint(equalToConstant: 200)
        ])
    }
    
    private func createDataSource() {
        collectionDataSource = UICollectionViewDiffableDataSource<Section, UIImage>(collectionView: collectionView) { (collectionView, indexPath, photo) -> UICollectionViewCell? in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: GalleryCell.self), for: indexPath) as! GalleryCell
            cell.set(photoModel: photo)
            return cell
        }
    }
    
    private func createSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, UIImage>()
        snapshot.appendSections([.gallery])
        snapshot.appendItems(presenter.photoUIImages, toSection: .gallery)
        collectionDataSource.apply(snapshot, animatingDifferences: true)
    }
    
    func getLayout() -> UICollectionViewLayout {
        let myGroup = getMyGroup()
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalWidth(0.3))
        //let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [leadingGroup, centerGroup, trealingGroup])
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [myGroup])
        let section = NSCollectionLayoutSection(group: group)
        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }
    
    private func getGroup() -> NSCollectionLayoutGroup {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalWidth(4.5))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = .init(top: 1, leading: 1, bottom: 1, trailing: 1)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1.0))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitem: item, count: 3)
        return group
    }
    
    private func getMyGroup() -> NSCollectionLayoutGroup {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.3), heightDimension: .fractionalWidth(0.3))
        print(itemSize)
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = .init(top: 1, leading: 1, bottom: 1, trailing: 1)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(0.3))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: 3)
        return group
    }
    
    private func getCenterGroup() -> NSCollectionLayoutGroup {
        let itemTopSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(2 / 3))
        let itemTop = NSCollectionLayoutItem(layoutSize: itemTopSize)
        itemTop.contentInsets = .init(top: 1, leading: 1, bottom: 1, trailing: 1)
        
        let itemBotSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1 / 3))
        let itemBot = NSCollectionLayoutItem(layoutSize: itemBotSize)
        itemBot.contentInsets = .init(top: 1, leading: 1, bottom: 1, trailing: 1)
        
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1.0))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [itemTop, itemBot])
        return group
    }
}

//MARK: - GalleryViewInput

extension GalleryViewController: GalleryViewInput {
    
    func didAppendData() {
        createSnapshot()
    }
    
    func didUpdateData() {
        createSnapshot()
        collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: true)
    }
    
    func didUpdateIndex(index: Int, total: Int){
        loadingMessage = String(index) + "/" + String(total)
        loadingLabel.sizeToFit()
    }
    
    func show(message: String) {
        let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: "Ok", style: .cancel)
        alertController.addAction(okAction)
        present(alertController, animated: true)
    }
    
    func loadingStart() {
        activityIndicator.startAnimating()
    }
    
    func loadingFinish() {
        activityIndicator.stopAnimating()
        isLoading = false
        searchBar.isHidden = false
    }
}

//MARK: - UICollectionViewDelegateFlowLayout

extension GalleryViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        presenter.didPressPhoto(by: indexPath.item)
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        presenter.willShowPhoto(by: indexPath.item)
    }
}

extension GalleryViewController: UISearchBarDelegate {
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let text = searchBar.text else { return }
        searchBar.resignFirstResponder()
        presenter.didPressSearch(by: text)
    }
}
