//
//  GalleryPresenter.swift
//  Gallery
//
//  Created by Alex on 17.02.2021.
//

import Foundation
import UIKit
import Photos

protocol GalleryViewOutput {
    var photoViewModels: [PhotoViewModel] { get }
    var photoUIImages: [UIImage] { get }
    func viewDidLoad()
    func didPressSearch(by text: String)
    func didPressPhoto(by index: Int)
    func willShowPhoto(by index: Int)
}

protocol GalleryInteractorOutput: class {
    func didAppendPhotos(at indexArr: [Int])
    func didUpdatePhotos()
    func didCameError(_ error: Error)
    func didBuildIndex(index: Int, total: Int)
}

final class GalleryPresenter {
    
    //MARK: - Variables
    
    unowned var view: GalleryViewInput
    var interactor: GalleryInteractorInput!
    var router: GalleryRouterProtocol!
    
    var photoViewModels: [PhotoViewModel] = []
    var photoUIImages: [UIImage] = []
    
    init(view: GalleryViewInput) {
        self.view = view
        print("GalleryPresenter init")
    }
    
    deinit {
        print("GalleryPresenter deinit")
    }
}

//MARK: - GalleryViewOutput

extension GalleryPresenter: GalleryViewOutput {
    
    func viewDidLoad() {
        view.loadingStart()
        interactor.getPhotos()
    }
    
    func didPressPhoto(by index: Int) {
        router.showDetail(by: photoUIImages[index])
    }
    
    func didPressSearch(by text: String) {
        if self.interactor.isVectorReady == true {
            view.loadingStart()
            interactor.getSearchPhotos(by: text)
        } else {
            print("interactor not ready")
        }
    }
    
    func willShowPhoto(by index: Int) {
        interactor.willShowPhoto(by: index)
    }
}

extension GalleryPresenter: GalleryInteractorOutput {
        
    func didAppendPhotos(at indexArr: [Int]) {
        let photoViewModels = indexArr.map { PhotoViewModel(photo: interactor.photos[$0]) }
        self.photoViewModels.append(contentsOf: photoViewModels)
        view.didAppendData()
    }
    
    func didUpdatePhotos() {
        self.photoUIImages = interactor.showedImages
        view.loadingFinish()
        view.didUpdateData()
    }
    
    func didCameError(_ error: Error) {
        view.show(message: error.localizedDescription)
    }
    
    func didBuildIndex(index: Int, total: Int){
        view.didUpdateIndex(index: index, total: total)
    }
}


extension UIImage {
    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        guard let buffer = pixelBuffer, status == kCVReturnSuccess else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            context.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
            return pixelBuffer
        }
        return nil
    }
}
