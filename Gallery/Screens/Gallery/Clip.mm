//
//  Clip.mm
//  Gallery
//
//  Created by Frank, Yibo, Ashwin on 2023/4/15.
//
#import <opencv2/imgcodecs/imgcodecs_c.h>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/core/core_c.h>
#import <opencv2/highgui/highgui_c.h>
#import <opencv2/imgproc/imgproc_c.h>
#import <opencv2/opencv.hpp>
#import <LibTorch/LibTorch.h>
#import "Clip.h"
#import <sys/sysctl.h>
#import <mach/mach.h>
#import "annoylib.h"
#import "kissrandom.h"


using namespace Annoy;

// 获取当前设备可用内存(单位：MB）

@implementation SampleClass
- (double)availableMemory
{

  vm_statistics_data_t vmStats;
  mach_msg_type_number_t infoCount = HOST_VM_INFO_COUNT;
  kern_return_t kernReturn = host_statistics(mach_host_self(),
                                             HOST_VM_INFO,
                                             (host_info_t)&vmStats,
                                             &infoCount);
  if (kernReturn != KERN_SUCCESS) {
    return NSNotFound;
  }
  return ((vm_page_size *vmStats.free_count) / 1024.0) / 1024.0;
}

// 获取当前任务所占用的内存（单位：MB）

- (double)usedMemory
{
  task_basic_info_data_t taskInfo;
  mach_msg_type_number_t infoCount = TASK_BASIC_INFO_COUNT;
  kern_return_t kernReturn = task_info(mach_task_self(),
                                       TASK_BASIC_INFO,
                                       (task_info_t)&taskInfo,
                                       &infoCount);
  if (kernReturn != KERN_SUCCESS
      ) {
    return NSNotFound;
  }
  return taskInfo.resident_size / 1024.0 / 1024.0;
}
@end



const double mean_[3] = {0.48145466, 0.4578275, 0.40821073};
const double std_[3] = {0.26862954, 0.26130258, 0.27577711};
AnnoyIndex<int, float, DotProduct, Kiss32Random, AnnoyIndexMultiThreadedBuildPolicy> _index(512);

@implementation TorchModule {
 @protected
  torch::jit::script::Module _impl;
  
}
- (nullable instancetype)initWithFileAtPath:(NSString*)filePath {
  self = [super init];
  if (self) {
    try {
      auto qengines = at::globalContext().supportedQEngines();
      if (std::find(qengines.begin(), qengines.end(), at::QEngine::QNNPACK) != qengines.end()) {
        at::globalContext().setQEngine(at::QEngine::QNNPACK);
      }
      _impl = torch::jit::load(filePath.UTF8String);
      _impl.eval();
    } catch (const std::exception& exception) {
      NSLog(@"%s", exception.what());
      return nil;
    }
  }
  return self;
}

- (nullable instancetype)init{
    self = [super init];
    if (self) {
      try {
        auto qengines = at::globalContext().supportedQEngines();
        if (std::find(qengines.begin(), qengines.end(), at::QEngine::QNNPACK) != qengines.end()) {
          at::globalContext().setQEngine(at::QEngine::QNNPACK);
        }
        NSFileManager *fm = [NSFileManager defaultManager];
          if ([fm fileExistsAtPath:@"/tmp/tree"]) {
              _index.load("/tmp/tree");
              NSLog(@"Annoy index loaded");
          }
      } catch (const std::exception& exception) {
        NSLog(@"%s", exception.what());
        return nil;
      }
    }
    return self;
}
@end



@implementation IndexingModule
- (nullable NSArray<NSNumber*>*)search:(NSArray<NSNumber*>*)query {
    float *query_vector = new float[512];
    int i=0;
    for(NSNumber *number in query) {
        query_vector[i++] = [number floatValue];
    }
    std::vector<int> results_ids;
    std::vector<float> distances;
    _index.get_nns_by_vector(query_vector, 30, -1, &results_ids, &distances);
    NSMutableArray* results = [[NSMutableArray alloc] init];
    for (int i = 0; i < results_ids.size(); i++) {
        if (i > 2 && distances[i] <= 28){
            break;
        }
      [results addObject:@(results_ids[i])];
    }
    return [results copy];
}

- (nullable NSArray<NSNumber*>*)buildIndexOne:(NSArray<NSNumber*>*)data {
    float *data_ = new float[512];
    int i=0;
    for(NSNumber *number in data) {
        data_[i++] = [number floatValue];
    }
    _index.add_item(_index._n_items, data_);
    delete[] data_;
    return NULL;
}

- (nullable NSArray<NSNumber*>*)save {
    _index.build(512*2);
    NSData *data = [[NSData alloc] initWithBytes:_index._nodes length:(_index._s*_index._n_nodes)];
    NSError *error = nil;
    BOOL saved =  [data writeToFile:@"/tmp/tree" options:NSDataWritingAtomic error:&error];
    std::cout<<"Index with " << _index._n_items << " samples built and saved:" << saved << "\n";
    return NULL;
}

- (nullable NSArray<NSNumber*>*)buildIndex:(NSArray<NSArray<NSNumber*>*>*)datas {
    int j=0;
    for(NSArray<NSNumber*> *array in datas) {
        float *data = new float[512];
        int i = 0;
        for(NSNumber *number in array) {
            data[i++] = [number floatValue];
        }
        _index.add_item(j, data);
        delete[] data;
        j++;
    }
    _index.build(512*2);
    NSData *data = [[NSData alloc] initWithBytes:_index._nodes length:(_index._s*_index._n_nodes)];
    NSError *error = nil;
    NSString *path = [NSHomeDirectory() stringByAppendingString:@"/Documents/index.plist"];
    BOOL saved =  [data writeToFile:path options:NSDataWritingAtomic error:&error];
    std::cout<<"Index with " << _index._n_items << " samples built and saved:" << saved << "\n";
    
    NSLog(@"File saved at: %@", path);
    
    if (! saved){
        NSLog(@"Unable to write file,%@", error.localizedDescription);
    }
    return nil;
}
@end



@implementation CLIPNLPTorchModule
- (NSArray<NSString*>*)test {
    
    NSLog(@"this is the test function of CLIPNLP module being calling hahahah");
  return nil;
}

- (NSArray<NSNumber*>*)encode:(NSArray*)ids {
  try {
      long token_ids[77] = {0};
      for(int i=0;i<ids.count;++i)
         token_ids[i] = [ids[i] longValue];
    torch::autograd::AutoGradMode guard(false);
    at::AutoNonVariableTypeMode non_var_type_mode(true);
    at::Tensor tensor = torch::from_blob((void*)token_ids, {1, 77}, at::kLong);
    auto outputTensor = _impl.forward({tensor}).toTensor();
    float* floatBuffer = outputTensor.data_ptr<float>();
//    t.add_item(0, floatBuffer);
//    t.build(2*512);
//      std::vector<int> res;
//      t.get_nns_by_item(0, 1, -1, &res, nullptr);
//      std::cout<<"query results:\n";
//      for(int i=0;i<res.size();++i)
//      std::cout<<res[i]<<"\n";
//      NSData *data = [[NSData alloc] initWithBytes:t._nodes length:(t._s*t._n_nodes)];
//      BOOL bb =  [data writeToFile:@"/tmp/tree" options:NSDataWritingAtomic error:&error];
//      std::cout<<bb;
//      t.load("tree.tree");
//      t.load("/tmp/tree");
//      t.get_nns_by_vector(floatBuffer, 1, -1, &res, nullptr);
    if (!floatBuffer) {
      return nil;
    }
    NSMutableArray* results = [[NSMutableArray alloc] init];
    for (int i = 0; i < 512; i++) {
      [results addObject:@(floatBuffer[i])];
    }
    return [results copy];
  } catch (const std::exception& exception) {
    NSLog(@"%s", exception.what());
  }
  return nil;
}
@end

@implementation CLIPImageTorchModule

- (NSArray<NSNumber*>*)encode:(void*)imageBuffer {
  try {
    cv::Mat img = cv::imread("test.png");
    cv::cvtColor(img, img, cv::COLOR_BGR2RGB);
    cv::resize(img, img, cv::Size(224, 224), 0, 0, cv::INTER_CUBIC);
    // centerSizeCrop(224)
    const int cropSize = 224;
    const int offsetW = std::round((img.cols - cropSize) / 2.0);
    const int offsetH = std::round((img.rows - cropSize) / 2.0);
    const cv::Rect roi(offsetW, offsetH, cropSize, cropSize);
    img = img(roi).clone();
    at::Tensor tensor = torch::from_blob(imageBuffer, {1, 3, 224, 224}, at::kFloat);
    torch::autograd::AutoGradMode guard(false);
    at::AutoNonVariableTypeMode non_var_type_mode(true);
    auto outputTensor = _impl.forward({tensor}).toTensor();
    float* floatBuffer = outputTensor.data_ptr<float>();
    if (!floatBuffer) {
      return nil;
    }
    NSMutableArray* results = [[NSMutableArray alloc] init];
    for (int i = 0; i < 512; i++) {
      [results addObject:@(floatBuffer[i])];
    }
    return [results copy];
  } catch (const std::exception& exception) {
    NSLog(@"%s", exception.what());
  }
  return nil;
}

- (nullable NSArray<NSArray<NSNumber*>*>*)encode_images:(NSArray<UIImage*>*)images {
    return nil;
}


- (NSArray<NSNumber*>*)test_uiimagetomat:(UIImage*)image {
    torch::autograd::AutoGradMode guard(false);
    at::AutoNonVariableTypeMode non_var_type_mode(true);
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    cv::Mat cvMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels (color channels + alpha)
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to  data
                                                   cols,                       // Width of bitmap
                                                   rows,                       // Height of bitmap
                                                   8,                          // Bits per component
                                                   cvMat.step[0],              // Bytes per row
                                                   colorSpace,                 // Colorspace
                                                   kCGImageAlphaNoneSkipLast |
                                                   kCGBitmapByteOrderDefault); // Bitmap info flags
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    cv::Mat input_img = cvMat;
//    cv::Mat input_img;
    cv::cvtColor(input_img, input_img, cv::COLOR_BGR2RGB);
    cv::resize(input_img, input_img, cv::Size(224, 224), 0, 0, cv::INTER_CUBIC);
    // to tensor
    torch::Tensor tensor_image = torch::from_blob(input_img.data, {1, input_img.rows, input_img.cols, 3}, at::kByte);
    tensor_image = tensor_image.to(at::kFloat).div(255);
    tensor_image = tensor_image.permute({0,3,1,2});

    // Normalize
    tensor_image[0][0] = tensor_image[0][0].sub_(mean_[0]).div_(std_[0]);
    tensor_image[0][1] = tensor_image[0][1].sub_(mean_[1]).div_(std_[1]);
    tensor_image[0][2] = tensor_image[0][2].sub_(mean_[2]).div_(std_[2]);

    auto outputTensor = _impl.forward({tensor_image}).toTensor();
    float* floatBuffer = outputTensor.data_ptr<float>();
    if (!floatBuffer) {
      return nil;
    }
    NSMutableArray* results = [[NSMutableArray alloc] init];
    for (int i = 0; i < 512; i++) {
      [results addObject:@(floatBuffer[i])];
    }
    return [results copy];
}

- (NSArray<NSString*>*)test:(NSString*)filePath {
    cv::Mat img = cv::imread(filePath.UTF8String);
    cv::Mat read_img = img;
    cv::Mat input_img;
    cv::cvtColor(read_img, input_img, cv::COLOR_BGR2RGB);
    cv::resize(input_img, input_img, cv::Size(224, 224), 0, 0, cv::INTER_CUBIC);
    
    // to tensor
    torch::Tensor tensor_image = torch::from_blob(input_img.data, {1, input_img.rows, input_img.cols, 3}, at::kByte);
    tensor_image = tensor_image.to(at::kFloat).div(255);
    tensor_image = tensor_image.permute({0,3,1,2});

    // Normalize
    tensor_image[0][0] = tensor_image[0][0].sub_(mean_[0]).div_(std_[0]);
    tensor_image[0][1] = tensor_image[0][1].sub_(mean_[1]).div_(std_[1]);
    tensor_image[0][2] = tensor_image[0][2].sub_(mean_[2]).div_(std_[2]);

    torch::autograd::AutoGradMode guard(false);
    at::AutoNonVariableTypeMode non_var_type_mode(true);
    auto outputTensor = _impl.forward({tensor_image}).toTensor();
    NSLog(@"this is the test function of CLIPImage module being calling hahahah");
  return nil;
}

@end
