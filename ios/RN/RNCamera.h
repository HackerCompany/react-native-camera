#import <AVFoundation/AVFoundation.h>
#import <React/RCTBridge.h>
#import <React/RCTBridgeModule.h>
#import <UIKit/UIKit.h>

#import "FaceDetectorManagerMlkit.h"
#import "BarcodeDetectorManagerMlkit.h"

@class RNCamera;

@interface RNCamera : UIView <AVCaptureMetadataOutputObjectsDelegate,
                              AVCaptureFileOutputRecordingDelegate,
                              AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate>

@property(nonatomic, strong) dispatch_queue_t sessionQueue;
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureDeviceInput *videoCaptureDeviceInput;
@property(nonatomic, strong) AVCapturePhotoOutput *stillImageOutput;
@property(nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;
@property(nonatomic, strong) AVCaptureMetadataOutput *metadataOutput;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) id runtimeErrorHandlingObserver;
@property(nonatomic, strong) NSArray *barCodeTypes;
@property(nonatomic, strong) NSArray *googleVisionBarcodeTypes;

@property(nonatomic, assign) NSInteger presetCamera;
@property(nonatomic, copy) NSString *cameraId; // copy required for strings/pointers
@property(assign, nonatomic) NSInteger flashMode;
@property(assign, nonatomic) CGFloat zoom;
@property(assign, nonatomic) CGFloat maxZoom;
@property(assign, nonatomic) NSInteger autoFocus;
@property(copy, nonatomic) NSDictionary *autoFocusPointOfInterest;
@property(assign, nonatomic) float focusDepth;
@property(assign, nonatomic) NSInteger whiteBalance;
@property(assign, nonatomic) float exposure;
@property(assign, nonatomic) float exposureIsoMin;
@property(assign, nonatomic) float exposureIsoMax;
@property(assign, nonatomic) AVCaptureSessionPreset pictureSize;
@property(nonatomic, assign) BOOL isReadingBarCodes;
@property(nonatomic, assign) BOOL isRecordingInterrupted;
@property(nonatomic, assign) BOOL canReadText;
@property(nonatomic, assign) BOOL useNativeZoom;
@property(nonatomic, assign) BOOL didCapture;
@property(nonatomic, assign) BOOL captureWarmup;
@property(nonatomic, assign) BOOL captureTeardown;
@property(nonatomic, assign) CMSampleBufferRef lastFrame;


@property(nonatomic, assign) CGRect rectOfInterest;
@property(assign, nonatomic) AVVideoCodecType videoCodecType;
@property(assign, nonatomic)
    AVCaptureVideoStabilizationMode videoStabilizationMode;
@property(assign, nonatomic, nullable) NSNumber *defaultVideoQuality;
@property(assign, nonatomic, nullable) NSNumber *deviceOrientation;
@property(assign, nonatomic, nullable) NSNumber *orientation;
@property (nonatomic, assign) int width;
@property (nonatomic, assign) int height;

- (id)initWithBridge:(RCTBridge *)bridge;
- (void)updateType;
- (void)updateFlashMode;
- (void)updateFocusMode;
- (void)updateFocusDepth;
- (void)updateAutoFocusPointOfInterest;
- (void)updateZoom;
- (void)updateWhiteBalance;
- (void)updateExposure;
- (void)updatePictureSize;

- (void)updateRectOfInterest;

- (void)takePicture:(NSDictionary *)options
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject;
- (void)takePictureWithOrientation:(NSDictionary *)options
                           resolve:(RCTPromiseResolveBlock)resolve
                            reject:(RCTPromiseRejectBlock)reject;
- (void)resumePreview;
- (void)pausePreview;
- (void)setupOrDisablePinchZoom;
- (void)setupOrDisableBarcodeScanner;

- (void)onReady:(NSDictionary *)event;
- (void)onMountingError:(NSDictionary *)event;
- (void)onCodeRead:(NSDictionary *)event;
- (void)onPictureTaken:(NSDictionary *)event;
- (void)onPictureSaved:(NSDictionary *)event;
- (void)onRecordingStart:(NSDictionary *)event;
- (void)onRecordingEnd:(NSDictionary *)event;
- (void)onText:(NSDictionary *)event;
- (bool)isRecording;
- (void)onSubjectAreaChanged:(NSDictionary *)event;

@end
