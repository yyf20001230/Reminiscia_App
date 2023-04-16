//
//  GalleryRouter.swift
//  Gallery
//
//  Created by Alex on 17.02.2021.
//

import UIKit
import Photos

protocol GalleryRouterProtocol {
    func showDetail(by image: UIImage)
    func showDetailById(by id: String)
}

final class GalleryRouter {
    
    unowned let view: UIViewController
    
    init(view: UIViewController) {
        self.view = view
    }
}

//MARK: - GalleryRouterProtocol

extension GalleryRouter: GalleryRouterProtocol {
    
    func showDetail(by image: UIImage) {
        
       
        let detailVC = DetailBilder.getDetailVC(by: image)
        self.view.present(detailVC, animated: true)
    }
        
    func showDetailById(by id: String) {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: options)
        
        if let asset = fetchResult.firstObject {
            let imageManager = PHImageManager.default()

            imageManager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: nil, resultHandler: { (image: UIImage?, info:[AnyHashable:Any]?) in
                
                let detailVC = DetailBilder.getDetailVC(by: image!)
                self.view.present(detailVC, animated: true)
                
            })
        }
    }
}
