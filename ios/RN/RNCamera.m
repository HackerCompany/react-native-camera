#import "RNCamera.h"
#import "RNCameraUtils.h"
#import "RNImageUtils.h"
#import "RNFileSystem.h"
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/UIView+React.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Vision/Vision.h>
#import  "RNSensorOrientationChecker.h"

@interface RNCamera ()

@property (nonatomic, weak) RCTBridge *bridge;
@property (nonatomic,strong) RNSensorOrientationChecker * sensorOrientationChecker;

@property (nonatomic,strong) UIPinchGestureRecognizer *pinchGestureRecognizer;
@property (nonatomic, strong) RCTPromiseResolveBlock videoRecordedResolve;
@property (nonatomic, strong) RCTPromiseRejectBlock videoRecordedReject;

@property (nonatomic, copy) RCTDirectEventBlock onCameraReady;
@property (nonatomic, copy) RCTDirectEventBlock onMountError;
@property (nonatomic, copy) RCTDirectEventBlock onBarCodeRead;
@property (nonatomic, copy) RCTDirectEventBlock onTextRecognized;

@property (nonatomic, copy) RCTDirectEventBlock onPictureTaken;
@property (nonatomic, copy) RCTDirectEventBlock onPictureSaved;
@property (nonatomic, copy) RCTDirectEventBlock onRecordingStart;
@property (nonatomic, copy) RCTDirectEventBlock onRecordingEnd;
@property (nonatomic, assign) BOOL finishedReadingText;
@property (nonatomic, copy) NSDate *startText;
@property (nonatomic, copy) NSDate *startFace;
@property (nonatomic, copy) NSDate *startBarcode;

@property (nonatomic, copy) RCTDirectEventBlock onSubjectAreaChanged;
@property (nonatomic, assign) BOOL isFocusedOnPoint;
@property (nonatomic, assign) BOOL isExposedOnPoint;

@end

@implementation RNCamera

static NSDictionary *defaultFaceDetectorOptions = nil;

BOOL _recordRequested = NO;
BOOL _sessionInterrupted = NO;


- (id)initWithBridge:(RCTBridge *)bridge
{
    if ((self = [super init])) {
        self.bridge = bridge;
        self.width = 0;
        self.height = 0;
        self.session = [AVCaptureSession new];
        self.sessionQueue = dispatch_queue_create("cameraQueue", DISPATCH_QUEUE_SERIAL);
        self.sensorOrientationChecker = [RNSensorOrientationChecker new];
        self.finishedReadingText = true;
        self.startText = [NSDate date];
        self.startFace = [NSDate date];
        self.startBarcode = [NSDate date];
#if !(TARGET_IPHONE_SIMULATOR)
        self.previewLayer =
        [AVCaptureVideoPreviewLayer layerWithSession:self.session];
        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        self.previewLayer.needsDisplayOnBoundsChange = YES;
#endif
        self.rectOfInterest = CGRectMake(0, 0, 1.0, 1.0);
        self.autoFocus = -1;
        self.exposure = -1;
        self.presetCamera = AVCaptureDevicePositionUnspecified;
        self.cameraId = nil;
        self.isFocusedOnPoint = NO;
        self.isExposedOnPoint = NO;
        self.didCapture = NO;
        self.captureWarmup = NO;
        self.captureTeardown = NO;
        _recordRequested = NO;
        _sessionInterrupted = NO;

        // we will do other initialization after
        // the view is loaded.
        // This is to prevent code if the view is unused as react
        // might create multiple instances of it.
        // and we need to also add/remove event listeners.


    }
    return self;
}
-(float) getMaxZoomFactor:(AVCaptureDevice*)device {
    float maxZoom;
    if(self.maxZoom > 1){
        maxZoom = MIN(self.maxZoom, device.activeFormat.videoMaxZoomFactor);
    }else{
        maxZoom = device.activeFormat.videoMaxZoomFactor;
    }
    return maxZoom;
}

-(void) handlePinchToZoomRecognizer:(UIPinchGestureRecognizer*)pinchRecognizer {
    const CGFloat pinchVelocityDividerFactor = 5.0f;

    if (pinchRecognizer.state == UIGestureRecognizerStateChanged) {
        AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
        if(device == nil){
            return;
        }
        NSError *error = nil;
        float maxZoom = [self getMaxZoomFactor:device];
        if ([device lockForConfiguration:&error]) {
            CGFloat desiredZoomFactor = device.videoZoomFactor + atan2f(pinchRecognizer.velocity, pinchVelocityDividerFactor);
            // Check if desiredZoomFactor fits required range from 1.0 to activeFormat.videoMaxZoomFactor
            device.videoZoomFactor = MAX(1.0, MIN(desiredZoomFactor, maxZoom));
            [device unlockForConfiguration];
        } else {
            NSLog(@"error: %@", error);
        }
    }
}

- (void)onReady:(NSDictionary *)event
{
    if (_onCameraReady) {
        _onCameraReady(nil);
    }
}


- (void)onMountingError:(NSDictionary *)event
{
    if (_onMountError) {
        _onMountError(event);
    }
}

- (void)onCodeRead:(NSDictionary *)event
{
    if (_onBarCodeRead) {
        _onBarCodeRead(event);
    }
}

- (void)onPictureTaken:(NSDictionary *)event
{
    if (_onPictureTaken) {
        _onPictureTaken(event);
    }
}

- (void)onPictureSaved:(NSDictionary *)event
{
    if (_onPictureSaved) {
        _onPictureSaved(event);
    }
}

- (void)onRecordingStart:(NSDictionary *)event
{
    if (_onRecordingStart) {
        _onRecordingStart(event);
    }
}

- (void)onRecordingEnd:(NSDictionary *)event
{
    if (_onRecordingEnd) {
        _onRecordingEnd(event);
    }
}

- (void)onText:(NSDictionary *)event
{
    if (_onTextRecognized && _session) {
        _onTextRecognized(event);
    }
}

- (void)onSubjectAreaChanged:(NSDictionary *)event
{
    if (_onSubjectAreaChanged) {
        _onSubjectAreaChanged(event);
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.previewLayer.frame = self.bounds;
    [self setBackgroundColor:[UIColor blackColor]];
    [self.layer insertSublayer:self.previewLayer atIndex:0];
}

- (void)insertReactSubview:(UIView *)view atIndex:(NSInteger)atIndex
{
    [self insertSubview:view atIndex:atIndex + 1]; // is this + 1 really necessary?
    [super insertReactSubview:view atIndex:atIndex];
    return;
}

- (void)removeReactSubview:(UIView *)subview
{
    [subview removeFromSuperview];
    [super removeReactSubview:subview];
    return;
}


- (void)willMoveToSuperview:(nullable UIView *)newSuperview;
{
    if(newSuperview != nil){

        [[NSNotificationCenter defaultCenter] addObserver:self
         selector:@selector(orientationChanged:)
             name:UIApplicationDidChangeStatusBarOrientationNotification
           object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionDidStartRunning:) name:AVCaptureSessionDidStartRunningNotification object:self.session];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];

        // this is not needed since RN will update our type value
        // after mount to set the camera's default, and that will already
        // this method
        // [self initializeCaptureSessionInput];
        [self startSession];
    }
    else{
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];

        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionWasInterruptedNotification object:self.session];

        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionDidStartRunningNotification object:self.session];

        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureSessionRuntimeErrorNotification object:self.session];


        [self stopSession];
    }

    [super willMoveToSuperview:newSuperview];
}



// Helper to get a device from the currently set properties (type and camera id)
// might return nil if device failed to be retrieved or is invalid
-(AVCaptureDevice*)getDevice
{
    return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInTrueDepthCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
}

// helper to return the camera's instance default preset
// this is for pictures only, and video should set another preset
// before recording.
// This default preset returns much smoother photos than High.
-(AVCaptureSessionPreset)getDefaultPreset
{
    return AVCaptureSessionPreset1280x720;
}


-(void)updateType
{
    [self initializeCaptureSessionInput];
    [self startSession]; // will already check if session is running
}


- (void)updateFlashMode
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (self.flashMode == RNCameraFlashModeTorch) {
        if (![device hasTorch])
            return;
        if (![device lockForConfiguration:&error]) {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
            return;
        }
        if (device.hasTorch && [device isTorchModeSupported:AVCaptureTorchModeOn])
        {
            NSError *error = nil;
            if ([device lockForConfiguration:&error]) {
                [device setFlashMode:AVCaptureFlashModeOff];
                [device setTorchMode:AVCaptureTorchModeOn];
                [device unlockForConfiguration];
            } else {
                if (error) {
                    RCTLogError(@"%s: %@", __func__, error);
                }
            }
        }
    } else {
        if (![device hasFlash])
            return;
        if (![device lockForConfiguration:&error]) {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
            return;
        }
        if (device.hasFlash && [device isFlashModeSupported:self.flashMode])
        {
            NSError *error = nil;
            if ([device lockForConfiguration:&error]) {
                if ([device isTorchActive]) {
                    [device setTorchMode:AVCaptureTorchModeOff];
                }
                [device setFlashMode:self.flashMode];
                [device unlockForConfiguration];
            } else {
                if (error) {
                    RCTLogError(@"%s: %@", __func__, error);
                }
            }
        }
    }

    [device unlockForConfiguration];
}

// Function to cleanup focus listeners and variables on device
// change. This is required since "defocusing" might not be
// possible on the new device, and our device reference will be
// different
- (void)cleanupFocus:(AVCaptureDevice*) previousDevice {

    self.isFocusedOnPoint = NO;
    self.isExposedOnPoint = NO;

    // cleanup listeners if we had any
    if(previousDevice != nil){

        // remove event listener
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:previousDevice];

        // cleanup device flags
        NSError *error = nil;
        if (![previousDevice lockForConfiguration:&error]) {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
            return;
        }

        previousDevice.subjectAreaChangeMonitoringEnabled = NO;

        [previousDevice unlockForConfiguration];

    }
}

- (void)defocusPointOfInterest
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];


    if (self.isFocusedOnPoint) {

        self.isFocusedOnPoint = NO;

        if(device == nil){
            return;
        }

        device.subjectAreaChangeMonitoringEnabled = NO;
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:device];

        CGPoint prevPoint = [device focusPointOfInterest];

        CGPoint autofocusPoint = CGPointMake(0.5f, 0.5f);

        [device setFocusPointOfInterest: autofocusPoint];

        [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];

        [self onSubjectAreaChanged:@{
            @"prevPointOfInterest": @{
                @"x": @(prevPoint.x),
                @"y": @(prevPoint.y)
            }
        }];
    }

    if(self.isExposedOnPoint){
        self.isExposedOnPoint = NO;

        if(device == nil){
            return;
        }

        CGPoint exposurePoint = CGPointMake(0.5f, 0.5f);

        [device setExposurePointOfInterest: exposurePoint];

        [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
}

- (void)deexposePointOfInterest
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];


    if(self.isExposedOnPoint){
        self.isExposedOnPoint = NO;

        if(device == nil){
            return;
        }

        CGPoint exposurePoint = CGPointMake(0.5f, 0.5f);

        [device setExposurePointOfInterest: exposurePoint];

        [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
}


- (void)updateAutoFocusPointOfInterest
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    if ([self.autoFocusPointOfInterest objectForKey:@"x"] && [self.autoFocusPointOfInterest objectForKey:@"y"]) {

        float xValue = [self.autoFocusPointOfInterest[@"x"] floatValue];
        float yValue = [self.autoFocusPointOfInterest[@"y"] floatValue];

        CGPoint autofocusPoint = CGPointMake(xValue, yValue);


        if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {

            [device setFocusPointOfInterest:autofocusPoint];
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];

            if (!self.isFocusedOnPoint) {
                self.isFocusedOnPoint = YES;

                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(AutofocusDelegate:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:device];
                device.subjectAreaChangeMonitoringEnabled = YES;
            }
        } else {
            RCTLogWarn(@"AutoFocusPointOfInterest not supported");
        }

        if([self.autoFocusPointOfInterest objectForKey:@"autoExposure"]){
            BOOL autoExposure = [self.autoFocusPointOfInterest[@"autoExposure"] boolValue];

            if(autoExposure){
                if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
                {
                    [device setExposurePointOfInterest:autofocusPoint];
                    [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
                    self.isExposedOnPoint = YES;

                } else {
                    RCTLogWarn(@"AutoExposurePointOfInterest not supported");
                }
            }
            else{
                [self deexposePointOfInterest];
            }
        }
        else{
            [self deexposePointOfInterest];
        }

    } else {
        [self defocusPointOfInterest];
        [self deexposePointOfInterest];
    }

    [device unlockForConfiguration];
}

-(void) AutofocusDelegate:(NSNotification*) notification {
    AVCaptureDevice* device = [notification object];

    if ([device lockForConfiguration:NULL] == YES ) {
        [self defocusPointOfInterest];
        [self deexposePointOfInterest];
        [device unlockForConfiguration];
    }
}

- (void)updateFocusMode
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    if ([device isFocusModeSupported:self.autoFocus]) {
        if ([device lockForConfiguration:&error]) {
            [device setFocusMode:self.autoFocus];
        } else {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
        }
    }

    [device unlockForConfiguration];
}

- (void)updateFocusDepth
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if (device == nil || self.autoFocus < 0 || device.focusMode != RNCameraAutoFocusOff || device.position == RNCameraTypeFront) {
        return;
    }

    if (![device respondsToSelector:@selector(isLockingFocusWithCustomLensPositionSupported)] || ![device isLockingFocusWithCustomLensPositionSupported]) {
        RCTLogWarn(@"%s: Setting focusDepth isn't supported for this camera device", __func__);
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    __weak __typeof__(device) weakDevice = device;
    [device setFocusModeLockedWithLensPosition:self.focusDepth completionHandler:^(CMTime syncTime) {
        [weakDevice unlockForConfiguration];
    }];
}

- (void)updateZoom {
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    float maxZoom = [self getMaxZoomFactor:device];

    device.videoZoomFactor = (maxZoom - 1) * self.zoom + 1;


    [device unlockForConfiguration];
}

- (void)updateWhiteBalance
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    if (self.whiteBalance == RNCameraWhiteBalanceAuto) {
        [device setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        [device unlockForConfiguration];
    } else {
        AVCaptureWhiteBalanceTemperatureAndTintValues temperatureAndTint = {
            .temperature = [RNCameraUtils temperatureForWhiteBalance:self.whiteBalance],
            .tint = 0,
        };
        AVCaptureWhiteBalanceGains rgbGains = [device deviceWhiteBalanceGainsForTemperatureAndTintValues:temperatureAndTint];
        __weak __typeof__(device) weakDevice = device;
        if ([device lockForConfiguration:&error]) {
            @try{
                [device setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:rgbGains completionHandler:^(CMTime syncTime) {
                    [weakDevice unlockForConfiguration];
                }];
            }
            @catch(NSException *exception){
                RCTLogError(@"Failed to set white balance: %@", exception);
            }
        } else {
            if (error) {
                RCTLogError(@"%s: %@", __func__, error);
            }
        }
    }

    [device unlockForConfiguration];
}


/// Set the AVCaptureDevice's ISO values based on RNCamera's 'exposure' value,
/// which is a float between 0 and 1 if defined by the user or -1 to indicate that no
/// selection is active. 'exposure' gets mapped to a valid ISO value between the
/// device's min/max-range of ISO-values.
///
/// The exposure gets reset every time the user manually sets the autofocus-point in
/// 'updateAutoFocusPointOfInterest' automatically. Currently no explicit event is fired.
/// This leads to two 'exposure'-states: one here and one in the component, which is
/// fine. 'exposure' here gets only synced if 'exposure' on the js-side changes. You
/// can manually keep the state in sync by setting 'exposure' in your React-state
/// everytime the js-updateAutoFocusPointOfInterest-function gets called.
- (void)updateExposure
{
    AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
    NSError *error = nil;

    if(device == nil){
        return;
    }

    if (![device lockForConfiguration:&error]) {
        if (error) {
            RCTLogError(@"%s: %@", __func__, error);
        }
        return;
    }

    // Check that either no explicit exposure-val has been set yet
    // or that it has been reset. Check for > 1 is only a guard.
    if(self.exposure < 0 || self.exposure > 1){
        [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        [device unlockForConfiguration];
        return;
    }

    // Lazy init of range.
    if(!self.exposureIsoMin){ self.exposureIsoMin = device.activeFormat.minISO; }
    if(!self.exposureIsoMax){ self.exposureIsoMax = device.activeFormat.maxISO; }

    // Get a valid ISO-value in range from min to max. After we mapped the exposure
    // (a val between 0 - 1), the result gets corrected by the offset from 0, which
    // is the min-ISO-value.
    float appliedExposure = (self.exposureIsoMax - self.exposureIsoMin) * self.exposure + self.exposureIsoMin;

    // Make sure we're in AVCaptureExposureModeCustom, else the ISO + duration time won't apply.
    // Also make sure the device can set exposure
    if([device isExposureModeSupported:AVCaptureExposureModeCustom]){
        if(device.exposureMode != AVCaptureExposureModeCustom){
            [device setExposureMode:AVCaptureExposureModeCustom];
        }

        // Only set the ISO for now, duration will be default as a change might affect frame rate.
        [device setExposureModeCustomWithDuration:AVCaptureExposureDurationCurrent ISO:appliedExposure completionHandler:nil];
    }
    else{
        RCTLog(@"Device does not support AVCaptureExposureModeCustom");
    }
    [device unlockForConfiguration];
}

- (void)updatePictureSize
{
    // make sure to call this function so the right default is used if
    // "None" is used
    AVCaptureSessionPreset preset = [self getDefaultPreset];
    if (self.session.sessionPreset != preset) {
        [self updateSessionPreset: preset];
    }
}


- (void)takePictureWithOrientation:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject{
    [self takePicture:nil resolve:resolve reject:reject];
}

- (void)takePicture:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
    // if video device is not set, reject
    if(self.videoCaptureDeviceInput == nil || !self.session.isRunning){
        reject(@"E_IMAGE_CAPTURE_FAILED", @"Camera is not ready.", nil);
        return;
    }
    self.didCapture = YES;
}

- (void)resumePreview
{
    [[self.previewLayer connection] setEnabled:YES];
}

- (void)pausePreview
{
    [[self.previewLayer connection] setEnabled:NO];
}

- (void)startSession
{
#if TARGET_IPHONE_SIMULATOR
    [self onReady:nil];
    return;
#endif
    dispatch_async(self.sessionQueue, ^{

        // if session already running, also return and fire ready event
        // this is helpfu when the device type or ID is changed and we must
        // receive another ready event (like Android does)
        if(self.session.isRunning){
            [self onReady:nil];
            return;
        }

        // if camera not set (invalid type and no ID) return.
        if (self.presetCamera == AVCaptureDevicePositionUnspecified && self.cameraId == nil) {
            return;
        }

        // video device was not initialized, also return
        if(self.videoCaptureDeviceInput == nil){
            return;
        }


        AVCapturePhotoOutput *stillImageOutput = [[AVCapturePhotoOutput alloc] init];
        [stillImageOutput setMaxPhotoQualityPrioritization:AVCapturePhotoQualityPrioritizationQuality];
        [[stillImageOutput connectionWithMediaType:AVMediaTypeVideo ] setVideoOrientation:AVCaptureVideoOrientationPortrait];

        [self.session setSessionPreset:AVCaptureSessionPreset1280x720];
        if ([self.session canAddOutput:stillImageOutput]) {
            [self.session addOutput:stillImageOutput];
            self.stillImageOutput = stillImageOutput;
            [stillImageOutput setDepthDataDeliveryEnabled:YES];
            [stillImageOutput setEnabledSemanticSegmentationMatteTypes:@[AVSemanticSegmentationMatteTypeSkin, AVSemanticSegmentationMatteTypeHair]];
        }
        
        AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        [[videoOutput connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:AVCaptureVideoOrientationPortrait];

        NSMutableDictionary *options = [[NSMutableDictionary alloc] init];
        [videoOutput setAlwaysDiscardsLateVideoFrames:YES];
        //[videoOutput setVideoSettings:@{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) }];
        [videoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
           
        if ([self.session canAddOutput:videoOutput]) {
            [self.session addOutput:videoOutput];
        }
        
        [self setupOrDisableBarcodeScanner];

        _sessionInterrupted = NO;
        [self.session startRunning];
        self.didCapture = NO;
        [self onReady:nil];
    });
}

- (void)stopSession
{
#if TARGET_IPHONE_SIMULATOR
    return;
#endif
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.lastFrame != nil) {
            [self processSampleBuffer:self.lastFrame asType:@"teardown"];
        }
    });
       dispatch_async(self.sessionQueue, ^{
    
           [self.previewLayer removeFromSuperlayer];
           [self.session commitConfiguration];
           [self.session stopRunning];

           for (AVCaptureInput *input in self.session.inputs) {
               [self.session removeInput:input];
           }

           for (AVCaptureOutput *output in self.session.outputs) {
               [self.session removeOutput:output];
           }


           // clean these up as well since we've removed
           // all inputs and outputs from session
           self.videoCaptureDeviceInput = nil;
           self.movieFileOutput = nil;
       });
}

- (void)initializeCaptureSessionInput
{

    dispatch_async(self.sessionQueue, ^{

        // Do all camera initialization in the session queue
        // to prevent it from
        AVCaptureDevice *captureDevice = [self getDevice];

        // if setting a new device is the same we currently have, nothing to do
        // return.
        if(self.videoCaptureDeviceInput != nil && captureDevice != nil && [self.videoCaptureDeviceInput.device.uniqueID isEqualToString:captureDevice.uniqueID]){
            return;
        }

        // if the device we are setting is also invalid/nil, return
        if(captureDevice == nil){
            [self onMountingError:@{@"message": @"Invalid camera device."}];
            return;
        }

        // get orientation also in our session queue to prevent
        // race conditions and also blocking the main thread
        __block UIInterfaceOrientation interfaceOrientation;

        dispatch_sync(dispatch_get_main_queue(), ^{
            interfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
        });

        AVCaptureVideoOrientation orientation = [RNCameraUtils videoOrientationForInterfaceOrientation:interfaceOrientation];


        [self.session beginConfiguration];

        NSError *error = nil;
        AVCaptureDeviceInput *captureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];

        if(error != nil){
            NSLog(@"Capture device error %@", error);
        }

        if (error || captureDeviceInput == nil) {
            RCTLog(@"%s: %@", __func__, error);
            [self.session commitConfiguration];
            [self onMountingError:@{@"message": @"Failed to setup capture device."}];
            return;
        }


        // Do additional cleanup that might be needed on the
        // previous device, if any.
        AVCaptureDevice *previousDevice = self.videoCaptureDeviceInput != nil ? self.videoCaptureDeviceInput.device : nil;

        [self cleanupFocus:previousDevice];


        // Remove inputs
        [self.session removeInput:self.videoCaptureDeviceInput];

        // clear this variable before setting it again.
        // Otherwise, if setting fails, we end up with a stale value.
        // and we are no longer able to detect if it changed or not
        self.videoCaptureDeviceInput = nil;

        // setup our capture preset based on what was set from RN
        // and our defaults
        // if the preset is not supported (e.g., when switching cameras)
        // canAddInput below will fail
        self.session.sessionPreset = [self getDefaultPreset];


        if ([self.session canAddInput:captureDeviceInput]) {
            [self.session addInput:captureDeviceInput];

            self.videoCaptureDeviceInput = captureDeviceInput;


            // Update all these async after our session has commited
            // since some values might be changed on session commit.
            dispatch_async(self.sessionQueue, ^{
                [self updateZoom];
                [self updateFocusMode];
                [self updateFocusDepth];
                //[self updateExposure];
                [self updateAutoFocusPointOfInterest];
                [self updateWhiteBalance];
                [self updateFlashMode];
            });

            [self.previewLayer.connection setVideoOrientation:orientation];
            [self _updateMetadataObjectsToRecognize];
        }
        else{
            RCTLog(@"The selected device does not work with the Preset [%@] or configuration provided", self.session.sessionPreset);

            [self onMountingError:@{@"message": @"Camera device does not support selected settings."}];
        }
        [self.stillImageOutput setDepthDataDeliveryEnabled:YES];

        [self.session commitConfiguration];
    });
}

#pragma mark - internal

- (void)updateSessionPreset:(AVCaptureSessionPreset)preset
{
#if !(TARGET_IPHONE_SIMULATOR)
    if ([preset integerValue] < 0) {
        return;
    }
    if (preset) {
        dispatch_async(self.sessionQueue, ^{
            if ([self.session canSetSessionPreset:preset]) {
                [self.session beginConfiguration];
                self.session.sessionPreset = preset;
                [self.session commitConfiguration];

                // Need to update these since it gets reset on preset change
                [self updateFlashMode];
                [self updateZoom];
            }
            else{
                RCTLog(@"The selected preset [%@] does not work with the current session.", preset);
            }
        });
    }
#endif
}


// We are using this event to detect audio interruption ended
// events since we won't receive it on our session



// session interrupted events
- (void)sessionWasInterrupted:(NSNotification *)notification
{
    // Mark session interruption
    _sessionInterrupted = YES;

    // Turn on video interrupted if our session is interrupted
    // for any reason
    if ([self isRecording]) {
        self.isRecordingInterrupted = YES;
    }

    // prevent any video recording start that we might have on the way
    _recordRequested = NO;

    // get event info and fire RN event if our session was interrupted
    // due to audio being taken away.
    NSDictionary *userInfo = notification.userInfo;
    NSInteger type = [[userInfo valueForKey:AVCaptureSessionInterruptionReasonKey] integerValue];


}


// update flash and our interrupted flag on session resume
- (void)sessionDidStartRunning:(NSNotification *)notification
{
    //NSLog(@"sessionDidStartRunning Was interrupted? %d", _sessionInterrupted);

    if(_sessionInterrupted){
        // resume flash value since it will be resetted / turned off
        dispatch_async(self.sessionQueue, ^{
            [self updateFlashMode];
        });
    }

    _sessionInterrupted = NO;
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    // Manually restarting the session since it must
    // have been stopped due to an error.
    dispatch_async(self.sessionQueue, ^{
         _sessionInterrupted = NO;
        [self.session startRunning];
        [self onReady:nil];
    });
}

- (void)orientationChanged:(NSNotification *)notification
{
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    [self changePreviewOrientation:orientation];
}

- (void)changePreviewOrientation:(UIInterfaceOrientation)orientation
{
    __weak typeof(self) weakSelf = self;
    AVCaptureVideoOrientation videoOrientation = [RNCameraUtils videoOrientationForInterfaceOrientation:orientation];
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.previewLayer.connection.isVideoOrientationSupported) {
            [strongSelf.previewLayer.connection setVideoOrientation:videoOrientation];
        }
    });
}
-(UIPinchGestureRecognizer*)createUIPinchGestureRecognizer
{
    return [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchToZoomRecognizer:)];
}
- (void)setupOrDisablePinchZoom
{
    if([self useNativeZoom]){
        self.pinchGestureRecognizer=[self createUIPinchGestureRecognizer];
        [self addGestureRecognizer:self.pinchGestureRecognizer];
    }else{
        [self removeGestureRecognizer:self.pinchGestureRecognizer];
        self.pinchGestureRecognizer=nil;
    }
}

# pragma mark - AVCaptureMetadataOutput

- (void)setupOrDisableBarcodeScanner
{
    [self _setupOrDisableMetadataOutput];
    [self _updateMetadataObjectsToRecognize];
}

- (void)updateRectOfInterest
{
    if (_metadataOutput == nil) {
        return;
    }
    [_metadataOutput setRectOfInterest: _rectOfInterest];
}

- (void)_setupOrDisableMetadataOutput
{
    if ([self isReadingBarCodes] && (_metadataOutput == nil || ![self.session.outputs containsObject:_metadataOutput])) {
        AVCaptureMetadataOutput *metadataOutput = [[AVCaptureMetadataOutput alloc] init];
        if ([self.session canAddOutput:metadataOutput]) {
            [metadataOutput setMetadataObjectsDelegate:self queue:self.sessionQueue];
            [self.session addOutput:metadataOutput];
            self.metadataOutput = metadataOutput;
        }
    } else if (_metadataOutput != nil && ![self isReadingBarCodes]) {
        [self.session removeOutput:_metadataOutput];
        _metadataOutput = nil;
    }
}

- (void)_updateMetadataObjectsToRecognize
{
    if (_metadataOutput == nil) {
        return;
    }

    NSArray<AVMetadataObjectType> *availableRequestedObjectTypes = [[NSArray alloc] init];
    NSArray<AVMetadataObjectType> *requestedObjectTypes = [NSArray arrayWithArray:self.barCodeTypes];
    NSArray<AVMetadataObjectType> *availableObjectTypes = _metadataOutput.availableMetadataObjectTypes;

    for(AVMetadataObjectType objectType in requestedObjectTypes) {
        if ([availableObjectTypes containsObject:objectType]) {
            availableRequestedObjectTypes = [availableRequestedObjectTypes arrayByAddingObject:objectType];
        }
    }

    [_metadataOutput setMetadataObjectTypes:availableRequestedObjectTypes];
    [self updateRectOfInterest];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection
{
    for(AVMetadataObject *metadata in metadataObjects) {
        if([metadata isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            AVMetadataMachineReadableCodeObject *codeMetadata = (AVMetadataMachineReadableCodeObject *) metadata;
            for (id barcodeType in self.barCodeTypes) {
                if ([metadata.type isEqualToString:barcodeType]) {
                    AVMetadataMachineReadableCodeObject *transformed = (AVMetadataMachineReadableCodeObject *)[_previewLayer transformedMetadataObjectForMetadataObject:metadata];
                    NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:@{
                        @"type" : codeMetadata.type,
                        @"data" : [NSNull null],
                        @"rawData" : [NSNull null],
                        @"bounds": @{
                            @"origin": @{
                                    @"x": [NSString stringWithFormat:@"%f", transformed.bounds.origin.x],
                                    @"y": [NSString stringWithFormat:@"%f", transformed.bounds.origin.y]
                                    },
                            @"size": @{
                                    @"height": [NSString stringWithFormat:@"%f", transformed.bounds.size.height],
                                    @"width": [NSString stringWithFormat:@"%f", transformed.bounds.size.width]
                                    }
                            }
                        }
                    ];

                    NSData *rawData;
                    // If we're on ios11 then we can use `descriptor` to access the raw data of the barcode.
                    // If we're on an older version of iOS we're stuck using valueForKeyPath to peak at the
                    // data.
                    if (@available(iOS 11, *)) {
                        // descriptor is a CIBarcodeDescriptor which is an abstract base class with no useful fields.
                        // in practice it's a subclass, many of which contain errorCorrectedPayload which is the data we
                        // want. Instead of individually checking the class types, just duck type errorCorrectedPayload
                        if ([codeMetadata.descriptor respondsToSelector:@selector(errorCorrectedPayload)]) {
                            rawData = [codeMetadata.descriptor performSelector:@selector(errorCorrectedPayload)];
                        }
                    } else {
                        rawData = [codeMetadata valueForKeyPath:@"_internal.basicDescriptor.BarcodeRawData"];
                    }

                    // Now that we have the raw data of the barcode translate it into a hex string to pass to the JS
                    const unsigned char *dataBuffer = (const unsigned char *)[rawData bytes];
                    if (dataBuffer) {
                        NSMutableString     *rawDataHexString  = [NSMutableString stringWithCapacity:([rawData length] * 2)];
                        for (int i = 0; i < [rawData length]; ++i) {
                            [rawDataHexString appendString:[NSString stringWithFormat:@"%02lx", (unsigned long)dataBuffer[i]]];
                        }
                        [event setObject:[NSString stringWithString:rawDataHexString] forKey:@"rawData"];
                    }

                    // If we were able to extract a string representation of the barcode, attach it to the event as well
                    // else just send null along.
                    if (codeMetadata.stringValue) {
                        [event setObject:codeMetadata.stringValue forKey:@"data"];
                    }

                    // Only send the event if we were able to pull out a binary or string representation
                    if ([event objectForKey:@"data"] != [NSNull null] || [event objectForKey:@"rawData"] != [NSNull null]) {
                        [self onCodeRead:event];
                    }
                }
            }
        }
    }
}

# pragma mark - AVCaptureMovieFileOutput

- (void)setupMovieFileCapture
{
    AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];

    if ([self.session canAddOutput:movieFileOutput]) {
        [self.session addOutput:movieFileOutput];
        self.movieFileOutput = movieFileOutput;
    }
}

- (void)cleanupMovieFileCapture
{
    if ([_session.outputs containsObject:_movieFileOutput]) {
        [_session removeOutput:_movieFileOutput];
        _movieFileOutput = nil;
    }
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    BOOL success = YES;
    if ([error code] != noErr) {
        NSNumber *value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
        if (value) {
            success = [value boolValue];
        }
    }
    if (success && self.videoRecordedResolve != nil) {
        NSMutableDictionary *result = [[NSMutableDictionary alloc] init];

        void (^resolveBlock)(void) = ^() {
            self.videoRecordedResolve(result);
        };

        result[@"uri"] = outputFileURL.absoluteString;
        result[@"videoOrientation"] = @([self.orientation integerValue]);
        result[@"deviceOrientation"] = @([self.deviceOrientation integerValue]);
        result[@"isRecordingInterrupted"] = @(self.isRecordingInterrupted);


        if (@available(iOS 10, *)) {
            AVVideoCodecType videoCodec = self.videoCodecType;
            if (videoCodec == nil) {
                videoCodec = [self.movieFileOutput.availableVideoCodecTypes firstObject];
            }
            result[@"codec"] = videoCodec;

            if ([connections[0] isVideoMirrored]) {
                [self mirrorVideo:outputFileURL completion:^(NSURL *mirroredURL) {
                    result[@"uri"] = mirroredURL.absoluteString;
                    resolveBlock();
                }];
                return;
            }
        }

        resolveBlock();
    } else if (self.videoRecordedReject != nil) {
        self.videoRecordedReject(@"E_RECORDING_FAILED", @"An error occurred while recording a video.", error);
    }

    [self cleanupCamera];

}

- (void)cleanupCamera {
    self.videoRecordedResolve = nil;
    self.videoRecordedReject = nil;
    self.videoCodecType = nil;
    self.deviceOrientation = nil;
    self.orientation = nil;
    self.isRecordingInterrupted = NO;


    // reset preset to current default
    AVCaptureSessionPreset preset = [self getDefaultPreset];
    if (self.session.sessionPreset != preset) {
        [self updateSessionPreset: preset];
    }
}

- (void)mirrorVideo:(NSURL *)inputURL completion:(void (^)(NSURL* outputUR))completion {
    AVAsset* videoAsset = [AVAsset assetWithURL:inputURL];
    AVAssetTrack* clipVideoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];

    AVMutableComposition* composition = [[AVMutableComposition alloc] init];
    [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];

    AVMutableVideoComposition* videoComposition = [[AVMutableVideoComposition alloc] init];
    videoComposition.renderSize = CGSizeMake(clipVideoTrack.naturalSize.height, clipVideoTrack.naturalSize.width);
    videoComposition.frameDuration = CMTimeMake(1, 30);

    AVMutableVideoCompositionLayerInstruction* transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:clipVideoTrack];

    AVMutableVideoCompositionInstruction* instruction = [[AVMutableVideoCompositionInstruction alloc] init];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(60, 30));

    CGAffineTransform transform = CGAffineTransformMakeScale(-1.0, 1.0);
    transform = CGAffineTransformTranslate(transform, -clipVideoTrack.naturalSize.width, 0);
    transform = CGAffineTransformRotate(transform, M_PI/2.0);
    transform = CGAffineTransformTranslate(transform, 0.0, -clipVideoTrack.naturalSize.width);

    [transformer setTransform:transform atTime:kCMTimeZero];

    [instruction setLayerInstructions:@[transformer]];
    [videoComposition setInstructions:@[instruction]];

    // Export
    AVAssetExportSession* exportSession = [AVAssetExportSession exportSessionWithAsset:videoAsset presetName:AVAssetExportPreset640x480];
    NSString* filePath = [RNFileSystem generatePathInDirectory:[[RNFileSystem cacheDirectoryPath] stringByAppendingString:@"CameraFlip"] withExtension:@".mp4"];
    NSURL* outputURL = [NSURL fileURLWithPath:filePath];
    [exportSession setOutputURL:outputURL];
    [exportSession setOutputFileType:AVFileTypeMPEG4];
    [exportSession setVideoComposition:videoComposition];
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        if (exportSession.status == AVAssetExportSessionStatusCompleted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(outputURL);
            });
        } else {
            NSLog(@"Export failed %@", exportSession.error);
        }
    }];
}

- (bool)isRecording {
    return self.movieFileOutput != nil ? self.movieFileOutput.isRecording : NO;
}

- (void)captureOutput:(AVCapturePhotoOutput *)output willCapturePhotoForResolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings {
    self.height = resolvedSettings.photoDimensions.height;
    self.width = resolvedSettings.photoDimensions.width;
}

- (CIImage *)handleMatteData:(AVCapturePhoto *)photo matteType:(AVSemanticSegmentationMatteType)ssmType {
    AVSemanticSegmentationMatte *matte = [photo semanticSegmentationMatteForType:ssmType];
    
    matte = [matte semanticSegmentationMatteByApplyingExifOrientation:kCGImagePropertyOrientationUp];
    
    NSDictionary<CIImageOption, id> *options = [[NSMutableDictionary alloc] init];
    if (ssmType == AVSemanticSegmentationMatteTypeHair) {
        if (@available(iOS 13.0, *)) {
            [options setValue:[NSNumber numberWithBool:YES] forKey:kCIImageAuxiliarySemanticSegmentationHairMatte];
        }
    }
    if (ssmType == AVSemanticSegmentationMatteTypeSkin) {
        if (@available(iOS 13.0, *)) {
            [options setValue:[NSNumber numberWithBool:YES] forKey:kCIImageAuxiliarySemanticSegmentationSkinMatte];
        }
    }
    return [[CIImage alloc] initWithCVImageBuffer:[matte mattingImage] options:@{}];
}

- (void)recognizeFacialLandmarks:(AVCapturePhoto *)photo {
    RNCamera *_self = self;

        VNDetectFaceLandmarksRequest *request = [[VNDetectFaceLandmarksRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        if (error != nil) {
            return;
        }
            NSArray<VNFaceObservation *> *results = request.results;
            if ([results count] == 0) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:@"" forKey:@"landmarks"];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"didReceiveLandmarks" object:nil userInfo:userInfo];
            }
            for (id result in results) {
                VNFaceLandmarks2D *landmarks = [result landmarks];
                VNFaceLandmarkRegion2D *faceContour = [landmarks faceContour];
                const CGPoint *hmm = [faceContour pointsInImageOfSize:CGSizeMake(self.width, self.height)];
                
                NSString *points = [NSString stringWithFormat:@"width:%d,height:%d|", self.height, self.width];

                
                for (int i = 0; i < [faceContour pointCount]; i++) {
                    CGPoint point = hmm[i];
                    points = [NSString stringWithFormat:@"%@\n%f,%f", points, point.y, point.x];
                }
                //[_self sendLandmarks:points];
                // SEND LANDMARKS
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:points forKey:@"landmarks"];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"didReceiveLandmarks" object:nil userInfo:userInfo];
            }
    }];
    NSMutableArray<VNRequest *> *requests = @[request];
    // TODO: Optimization?
    struct CGImage *cgImage = [photo CGImageRepresentation];
    
    VNImageRequestHandler *requestHandler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage orientation:kCGImagePropertyOrientationUp options:@{}];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [requestHandler performRequests:requests error:nil];
    });
}

- (CGImageRef)rotateImage:(CGImageRef)image {
    int originalWidth = CGImageGetWidth(image);
    int originalHeight = CGImageGetHeight(image);
    int bitsPerComponent = CGImageGetBitsPerComponent(image);
    int bytesPerRow = CGImageGetBytesPerRow(image);
    
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(image);
    
    double degreesToRotate = -90.0;
    double radians = degreesToRotate * M_PI / 180;
    
    int width = originalHeight;
    int height = originalWidth;
    
    CGContextRef contextRef = CGBitmapContextCreate(nil, width, height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
    
    CGContextTranslateCTM(contextRef, 0, height / 2);
    CGContextRotateCTM(contextRef, radians);
    CGContextScaleCTM(contextRef, 1.0, -1.0);
    CGContextTranslateCTM(contextRef, -height/2, -width);
    CGContextDrawImage(contextRef, CGRectMake(0, 0, originalWidth, originalHeight), image);
        
    CGImageRef orientedImage = CGBitmapContextCreateImage(contextRef);
    
    CGContextRelease(contextRef);

        
    return orientedImage;
}

- (CGImageRef)resizeImage:(CGImageRef)image {
    int originalWidth = CGImageGetWidth(image);
    int originalHeight = CGImageGetHeight(image);
    int bitsPerComponent = CGImageGetBitsPerComponent(image);
    int bytesPerRow = CGImageGetBytesPerRow(image);
    
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(image);
    
    double width = 720;
    double height = 1280;
    
    float scaleFactor = width / originalWidth;
    
    CGContextRef contextRef = CGBitmapContextCreate(nil, width, height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
    
    // CGContextScaleCTM(contextRef, scaleFactor, scaleFactor);
    CGContextDrawImage(contextRef, CGRectMake(0, 0, width, height), image);
    
    CGImageRef orientedImage = CGBitmapContextCreateImage(contextRef);
    
    CGContextRelease(contextRef);
    
    return orientedImage;
}

-(NSString *) randomStringWithLength: (int) len {

    NSString *letters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *randomString = [NSMutableString stringWithCapacity: len];

    for (int i=0; i<len; i++) {
         [randomString appendFormat: @"%C", [letters characterAtIndex: arc4random_uniform([letters length])]];
    }

    return randomString;
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer asType:(NSString *)type {
    @autoreleasepool {
        CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage *ciimage = [CIImage imageWithCVPixelBuffer:buffer];
        int width = ciimage.extent.size.width;
        int height = ciimage.extent.size.height;
        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef image = [context createCGImage:ciimage fromRect:ciimage.extent];
        context = nil;
        CGImageRef mirrored = [self rotateImage:image];
          NSURL *previewPath = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", [self randomStringWithLength:10]]];

          struct CGImageDestination *destination = CGImageDestinationCreateWithURL(CFBridgingRetain(previewPath), kUTTypeJPEG, 1, nil);

          CGImageDestinationAddImage(destination, mirrored, nil);
          CGImageDestinationFinalize(destination);
          CGImageRelease(image);
          CGImageRelease(mirrored);
          NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:[previewPath absoluteString] forKey:@"name"];
          [userInfo setValue:[NSString stringWithFormat:@"%d", width] forKey:@"width"];
          [userInfo setValue:[NSString stringWithFormat:@"%d", height] forKey:@"height"];

        if ([type isEqualToString:@"preview"]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"didReceivePreviewImage" object:nil userInfo:userInfo];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"didReceiveTeardownImage" object:nil userInfo:userInfo];
        }
    }
}

-(void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (self.lastFrame) {
        CFRelease(self.lastFrame);
    }
    CFRetain(sampleBuffer);
    self.lastFrame = sampleBuffer;
    if (self.didCapture) {
        self.didCapture = NO;
        [self processSampleBuffer:self.lastFrame asType:@"preview"];
        if (!self.captureTeardown) {
            AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
            [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
            AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettingsWithFormat:@{AVVideoCodecKey: AVVideoCodecJPEG}];
            [settings setEnabledSemanticSegmentationMatteTypes: @[AVSemanticSegmentationMatteTypeSkin, AVSemanticSegmentationMatteTypeHair]];
            [settings setDepthDataDeliveryEnabled:true];
            [settings setPhotoQualityPrioritization:AVCapturePhotoQualityPrioritizationQuality];
            [self.stillImageOutput capturePhotoWithSettings:settings delegate:self];
        }
        self.captureTeardown = NO;
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    NSLog(@"did drop a fram");
}


- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    [self recognizeFacialLandmarks:photo];
    output.depthDataDeliveryEnabled = true;
    NSURL *photoFileName = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:@"photo.jpg"];
    struct CGImageDestination *destination = CGImageDestinationCreateWithURL(CFBridgingRetain(photoFileName), kUTTypeJPEG, 1, nil);
    @autoreleasepool {
        // No need to release because obtained by CGImageRepresentation
        CGImageRef image = [photo CGImageRepresentation];

        CGImageRef newImage = [self rotateImage:image];

        CGImageDestinationAddImage(destination, newImage, nil);
        CGImageDestinationFinalize(destination);
        
        CGImageRelease(newImage);
    }

    
    NSString *payload = [NSString stringWithFormat:@"%@,%d,%d", [photoFileName absoluteString], self.width, self.height];
    
    NSMutableDictionary *photoDictionary = [NSMutableDictionary dictionaryWithObject:payload forKey:@"filename"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"didReceivePhoto" object:nil userInfo:photoDictionary];

    for (id matteType in [output enabledSemanticSegmentationMatteTypes]) {
        CIImage *img = [self handleMatteData:photo matteType:matteType];
        // TODO: Resize
        NSURL *matteFileName = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[NSString stringWithFormat:@"matte-%@.jpg", matteType]];
        @autoreleasepool {
            CIContext *context = [[CIContext alloc] init];
            CGImageRef matte = [context createCGImage:img fromRect:[img extent]];
            context = nil;
            CGImageRef rotatedMatte = [self rotateImage:matte];
            CGImageRef resizedMatte = [self resizeImage:rotatedMatte];
            
            struct CGImageDestination *matteDestination = CGImageDestinationCreateWithURL(CFBridgingRetain(matteFileName), kUTTypeJPEG, 1, nil);

            CGImageDestinationAddImage(matteDestination, resizedMatte, nil);
            CGImageDestinationFinalize(matteDestination);
            
            CGImageRelease(matte);
            CGImageRelease(resizedMatte);
            CGImageRelease(rotatedMatte);
        }
        
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:[matteFileName absoluteString] forKey:@"name"];
        if (matteType == AVSemanticSegmentationMatteTypeHair) {
            [userInfo setValue:@"AVSemanticSegmentationMatteTypeHair" forKey:@"type"];
        }
        if (matteType == AVSemanticSegmentationMatteTypeSkin) {
            [userInfo setValue:@"AVSemanticSegmentationMatteTypeSkin" forKey:@"type"];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"didReceiveMatte" object:nil userInfo:userInfo];
    }
}


@end
