//
//  GalleryInteractor.swift
//  Gallery
//
//  Created by Alex on 18.03.2021.
//

import Foundation
import Photos
import AVFoundation
import UIKit
import Accelerate
import Cereal
import CoreML

protocol GalleryInteractorInput {
    var photos: [Photo] { get }
    var localImages: [UIImage] { get }
    var showedImages: [UIImage] { get }
    var vectors: [[Float]] { get }
    var flat_vectors: [Float] { get }
    var isVectorReady: Bool { get }
    func getPhotos()
    func getSearchPhotos(by text: String)
    func willShowPhoto(by index: Int)
}

@available(iOS 14.0, *)
final class GalleryInteractor {
    
    unowned let presenter: GalleryInteractorOutput
    var networkService: NetworkServiceProtocol!
    var storeService: StoreServiceProtocol!
    var assetResults : PHFetchResult<AnyObject>!
    var view: UIViewController

    var photos: [Photo] = []
    var localImages: [UIImage] = []
    var showedImages: [UIImage] = []
    var vectors: [[Float]] = []
    var double_vectors: [[Double]] = []

    var flat_vectors: [Float] = []
    let n = vDSP_Length(512)
    let stride = vDSP_Stride(1)
    private var nextPageUrl: String?
    private var isLoading = false
    public var isVectorReady = false
    
    var tokenizer = Tokenizer()
    
    private var CLIPTextmodule: CLIPNLPTorchModule? = nil
    private var IndexModule: IndexingModule? = nil;

    
    //private var CLIPImagemodule: CLIPImageTorchModule? = nil
    private var ImageEncoder: CLIPImageEncoder? = nil
    
    init(presenter: GalleryInteractorOutput) {
        self.view = UIViewController()
        self.presenter = presenter
        self.tokenizer.loadJsons()
        print("GalleryInteractor init")
    }
    
    deinit {
        print("GalleryInteractor deinit")
    }
    
    //MARK: - Methods
    private func appendPhotos(_ response: Response) {
        storeService.addPhotos(response.photos)
        nextPageUrl = response.nextPageUrl
        let startIndex = self.photos.count
        photos.append(contentsOf: response.photos)
        let endIndex = self.photos.count
        let indexArr = (startIndex..<endIndex).map { Int($0) }
        presenter.didAppendPhotos(at: indexArr)
    }
    
    private func updatePhotos(_ response: Response) {
        storeService.deleteAllPhotos()
        storeService.addPhotos(response.photos)
        photos = []
        photos.append(contentsOf: response.photos)
        nextPageUrl = response.nextPageUrl
        presenter.didUpdatePhotos()
    }
    
    private func updateIndex(index: Int, total: Int){
        presenter.didBuildIndex(index: index, total: total)
    }
    
    //Image to CV Pixel BUffer
    private func buffer(from image: UIImage) -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 224, 224, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard (status == kCVReturnSuccess) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: 224, height: 224, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

        context?.translateBy(x: 0, y: 224)
        context?.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context!)
        image.draw(in: CGRect(x: 0, y: 0, width: 224, height: 224))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }

    private func preprocess(image: UIImage) -> CVPixelBuffer {
        let size = CGSize(width: 224, height: 224)

        guard let pixels = image.pixelBuffer(width: 224, height: 224) else {
            fatalError("Unable to convert the image")
        }

        print(">>> Finished preprocessing")

        return pixels
    }
}

//MARK: - GalleryInteractorInput

@available(iOS 14.0, *)
extension GalleryInteractor: GalleryInteractorInput {
    
    func getPhotos() {
        let albumName = "Lightroom"
        var photoAssets = PHFetchResult<AnyObject>()
        let fetchOptions = PHFetchOptions()

        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collection:PHFetchResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        guard let assetCollection = collection.firstObject else { fatalError("Album not found!") }
        
        /* Retrieve the items in order of modification date, ascending */
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: true)]
        photoAssets = PHAsset.fetchAssets(in: assetCollection, options: options) as! PHFetchResult<AnyObject>
        self.assetResults = photoAssets
        //self.assetResults = (PHAsset.fetchAssets(with: .image, options: options) as! PHFetchResult<AnyObject>)
        isLoading = true
        let imageManager = PHCachingImageManager()
        var flags: Array<Bool> = []
        var done: Bool = false
        
        self.assetResults.enumerateObjects{ [self](object: AnyObject, count: Int, stop: UnsafeMutablePointer<ObjCBool>) in
            if object is PHAsset {
                let asset = object as! PHAsset
                let imageSize = CGSize(width: 224, height: 224)

                /* For faster performance, and maybe degraded image */
                let options = PHImageRequestOptions()
                options.resizeMode = .exact
                options.deliveryMode = .highQualityFormat
                flags.append(false)
                options.isSynchronous = false
                if (count == assetResults.count-1) {
                    done = true
                }
                let idx: Int = flags.count-1
                print(">>>",idx,": ", asset.localIdentifier)

                imageManager.requestImage(for: asset,targetSize: imageSize, contentMode: .default, options: options, resultHandler: { (image: UIImage?, info:[AnyHashable:Any]?) in
                    
                    self.localImages.append(image!)
                    flags[idx] = true
                })
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            while done == false {}
            while true {
                var exit_:Bool = true
                for val in flags {
                    if (val==false) {
                        exit_ = false
                        break
                    }
                }
                if(exit_==true) {
                    break
                }
            }
            
            // Mobile app will remain to be responsive to user actions
            self.CLIPTextmodule = {
                if let filePath = Bundle.main.path(forResource: "text", ofType: "pt"),
                    let module = CLIPNLPTorchModule(fileAtPath: filePath) {
                    NSLog("CLIP Text encoder loaded")
                    return module
                } else {
                    fatalError("Failed to load clip nlp model!")
                }
            }()

            //check if index file exists
            let image_vector_local = UserDefaults.standard.object(forKey: "image_vector") as? [[NSNumber]]
            if (image_vector_local != nil && (image_vector_local!).count == 10000){
                print("image_vector_local found, building from existing source...")
                self.IndexModule = IndexingModule()
                self.IndexModule?.buildIndex(datas: image_vector_local!)
                print("finished fetch the existing source")
                
                
            } else {
                
                print("Error using the existing image source, building image from scratch...")
                
                
                self.ImageEncoder = try! CLIPImageEncoder()
                self.IndexModule = IndexingModule()
//                var encoder = CerealEncoder()
                let imageSize = CGSize(width: 224,height: 224)
                let options = PHImageRequestOptions()
                let imageManager_ = PHImageManager.default()
                options.deliveryMode = .fastFormat
                options.isSynchronous = true
                var image_vectors: Array<Array<Float>> = []
                
                var index = 0
                
                self.assetResults.enumerateObjects{ [self](object: AnyObject, count: Int, stop: UnsafeMutablePointer<ObjCBool>) in
                    print("progress: ", index, "/" , self.assetResults.count)
                    
                    
                    DispatchQueue.main.async { [self] in
                        updateIndex(index: index, total: self.assetResults.count)
                    }
                    
                    
                    index += 1
                    if object is PHAsset {
                        let asset = object as! PHAsset
                        autoreleasepool {
                            imageManager_.requestImage(for: asset, targetSize: imageSize, contentMode: PHImageContentMode.aspectFit, options: options, resultHandler: { (image: UIImage?, _) in
                                    image_vectors.append(self.CLIPImagemodule!.test_uiimagetomat(image: image!) as! Array<Float>)
                                
                                    self.IndexModule?.buildIndexOne(data: (self.CLIPImagemodule?.test_uiimagetomat(image: image!))!)
                                    self.CLIPImageModule?.test_uiimagetomat(image: image!)
                                
                                do {
                                    let MLArray = try self.ImageEncoder?.prediction(pixel_values: self.buffer(from: image!)!).var_1051

                                    // Init our output array
                                    var array: Array<Float> = []

                                    // Get length
                                    let length = MLArray!.count

                                    // Set content of multi array to our out put array
                                    for i in 0...length - 1 {
                                        array.append(Float(truncating: MLArray![[0,NSNumber(value: i)]]))
                                    }
                                    image_vectors.append(array)

                                } catch let error {
                                    print("Error occurred: \(error.localizedDescription)")
                                    fatalError("Some error")
                                }
                                
                            })
                        }
                    }
                }
                self.IndexModule?.buildIndex(datas: image_vectors as [[NSNumber]])
//                self.IndexModule?.save()
//                let vec = self.localImages.map{
//                    (self.CLIPImagemodule!.test_uiimagetomat(image:$0))! }
//                self.IndexModule?.buildIndex(datas: vec)
//                for id in 0..<vec.count {
//                    self.vectors.append(vec[id] as! [Float])
//                    let tmp_vec = vec[id] as! [Double]
//                    KMeans.sharedInstance.addVector(tmp_vec)
//                    try! encoder.encode(tmp_vec, forKey: String(id))
//                }
//                let data = encoder.toData()
//                try! data.write(to: URL(fileURLWithPath: vec_filePath))
                // indexing using KMeans
//                KMeans.sharedInstance.clusteringNumber = 4
//                KMeans.sharedInstance.dimension = 512
//                KMeans.sharedInstance.clustering(5)
//                var dictionary:NSMutableDictionary = [:]
//                dictionary["N"] = self.localImages.count
//                dictionary["centroids"] = KMeans.sharedInstance.finalCentroids
//                dictionary["clusters"] = KMeans.sharedInstance.finalClusters
//                dictionary["K"] = KMeans.sharedInstance.clusteringNumber
//                dictionary.write(toFile: filePath, atomically: true)
//                self.double_vectors = KMeans.sharedInstance.vectors
                
                UserDefaults.standard.set(image_vectors, forKey: "image_vector")
                
            }
            DispatchQueue.main.async {

                self.showedImages = self.localImages
                self.isLoading = false
                self.presenter.didUpdatePhotos()
                
            }
            self.isVectorReady = true
            print("done")
      }
    }
    
    func getSearchPhotos(by text: String) {
        isLoading = true
        if text == "reset" || text == "Reset" || text == "" {
            self.showedImages = self.localImages
            presenter.didUpdatePhotos()
            isLoading = false
            return
        }
        let token_ids = self.tokenizer.tokenize(text: text)
        let res = self.CLIPTextmodule!.encode(text: token_ids)
        let results_ids = self.IndexModule?.search(query: res!)
        self.showedImages = []
        let imageManager = PHCachingImageManager()
        let imageSize = CGSize(width: 224,height: 224)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = true
        for i in 0..<results_ids!.count {
            imageManager.requestImage(for: self.assetResults[Int(results_ids![i])] as! PHAsset, targetSize: imageSize, contentMode: PHImageContentMode.aspectFit, options: options, resultHandler: { (image: UIImage?, info:[AnyHashable:Any]?) in
                self.showedImages.append(image!)
            })
        }
//        let vector: [Double] = res! as! [Double]
//        // Mark: K-Means
//        let f_vector: [Float] = res as! [Float]
//        var max_centroid_id: Int = -1
//        var max_centroids_score: Double = .nan
//        for idx in 0..<KMeans.sharedInstance.finalCentroids.count {
//            let centroid = KMeans.sharedInstance.finalCentroids[idx]
//            var sim_score: Double = .nan
//            vDSP_dotprD(vector, self.stride, centroid, self.stride, &sim_score, self.n)
//            if max_centroids_score.isNaN || sim_score > max_centroids_score {
//                max_centroids_score = sim_score
//                max_centroid_id = idx
//            }
//        }
//        var final_sim_scores: [(score: Double, id: Int)] = []
//        for vec_id in KMeans.sharedInstance.finalClusters[max_centroid_id] {
//            var sim_score: Double = .nan
//            vDSP_dotprD(vector, self.stride, self.double_vectors[vec_id], self.stride, &sim_score, self.n)
////            vDSP_dotpr(f_vector, self.stride, self.vectors[vec_id], self.stride, &sim_score, self.n)
//            final_sim_scores.append((sim_score, vec_id))
//        }
//        final_sim_scores.sort { $0.score > $1.score } // sort in descending order by sim_score

//        for i in 0..<final_sim_scores.count {
//            self.showedImages.append(self.localImages[final_sim_scores[i].id])
//        }
        // Mark: Linear scan
//        var sim_scores: [(score: Float, id: Int)] = []
//        for idx in 0..<self.vectors.count {
//            var sim_score: Float = .nan
//            vDSP_dotpr(vector, self.stride, self.vectors[idx], self.stride, &sim_score, self.n)
//            sim_scores.append((sim_score, idx))
//        }
//        sim_scores.sort { $0.score > $1.score }
//        self.showedImages = []
//        for i in 0...2 {
//            self.showedImages.append(self.localImages[sim_scores[i].id])
//        }
        presenter.didUpdatePhotos()
        self.isLoading = false
    }
    
    func willShowPhoto(by index: Int) {
        if !isLoading,
           index >= photos.count - Constans.preLoadPhotoCount,
           let nextPageUrl = nextPageUrl {
            isLoading = true
            networkService.loadPhotosFrom(url: nextPageUrl) { (result) in
                switch result {
                case .failure(let error):
                    self.presenter.didCameError(error)
                case .success(let response):
                    self.appendPhotos(response)
                }
                self.isLoading = false
            }
        }
    }
}
