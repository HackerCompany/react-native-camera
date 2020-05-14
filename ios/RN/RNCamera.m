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
@property (nonatomic, strong) id textDetector;
@property (nonatomic, strong) id faceDetector;
@property (nonatomic, strong) id barcodeDetector;

@property (nonatomic, copy) RCTDirectEventBlock onCameraReady;
@property (nonatomic, copy) RCTDirectEventBlock onPhoto;
@property (nonatomic, copy) RCTDirectEventBlock onAudioInterrupted;
@property (nonatomic, copy) RCTDirectEventBlock onAudioConnected;
@property (nonatomic, copy) RCTDirectEventBlock onMountError;
@property (nonatomic, copy) RCTDirectEventBlock onBarCodeRead;
@property (nonatomic, copy) RCTDirectEventBlock onTextRecognized;
@property (nonatomic, copy) RCTDirectEventBlock onFacesDetected;
@property (nonatomic, copy) RCTDirectEventBlock onGoogleVisionBarcodesDetected;
@property (nonatomic, copy) RCTDirectEventBlock onPictureTaken;
@property (nonatomic, copy) RCTDirectEventBlock onPictureSaved;
@property (nonatomic, copy) RCTDirectEventBlock onRecordingStart;
@property (nonatomic, copy) RCTDirectEventBlock onRecordingEnd;
@property (nonatomic, assign) BOOL finishedReadingText;
@property (nonatomic, assign) BOOL finishedDetectingFace;
@property (nonatomic, assign) BOOL finishedDetectingBarcodes;
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
        self.textDetector = [self createTextDetector];
        self.faceDetector = [self createFaceDetectorMlKit];
        self.barcodeDetector = [self createBarcodeDetectorMlKit];
        self.finishedReadingText = true;
        self.finishedDetectingFace = true;
        self.finishedDetectingBarcodes = true;
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

- (void)onPhoto:(NSDictionary *)event
{
    if (_onPhoto) {
        _onPhoto(nil);
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

        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(audioDidInterrupted:)
            name:AVAudioSessionInterruptionNotification
            object:[AVAudioSession sharedInstance]];


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

        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];

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


- (void)updateCaptureAudio
{
    dispatch_async(self.sessionQueue, ^{
        if(self.captureAudio){
            [self initializeAudioCaptureSessionInput];
        }
        else{
            [self removeAudioCaptureSessionInput];
        }
    });
}

- (void)takePictureWithOrientation:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject{
    [self.sensorOrientationChecker getDeviceOrientationWithBlock:^(UIInterfaceOrientation orientation) {
        NSMutableDictionary *tmpOptions = [options mutableCopy];
        if ([tmpOptions valueForKey:@"orientation"] == nil) {
            tmpOptions[@"orientation"] = [NSNumber numberWithInteger:[self.sensorOrientationChecker convertToAVCaptureVideoOrientation:orientation]];
        }
        self.deviceOrientation = [NSNumber numberWithInteger:orientation];
        self.orientation = [NSNumber numberWithInteger:[tmpOptions[@"orientation"] integerValue]];
        [self takePicture:tmpOptions resolve:resolve reject:reject];
    }];
}

- (void)takePicture:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
    // if video device is not set, reject
    if(self.videoCaptureDeviceInput == nil || !self.session.isRunning){
        reject(@"E_IMAGE_CAPTURE_FAILED", @"Camera is not ready.", nil);
        return;
    }

    if (!self.deviceOrientation) {
        [self takePictureWithOrientation:options resolve:resolve reject:reject];
        return;
    }

    AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettingsWithFormat:@{AVVideoCodecKey: AVVideoCodecJPEG}];
    [self.stillImageOutput setDepthDataDeliveryEnabled:YES];
    [self.stillImageOutput setEnabledSemanticSegmentationMatteTypes:@[AVSemanticSegmentationMatteTypeSkin, AVSemanticSegmentationMatteTypeHair]];
    [settings setEnabledSemanticSegmentationMatteTypes: @[AVSemanticSegmentationMatteTypeSkin, AVSemanticSegmentationMatteTypeHair]];
    [settings setDepthDataDeliveryEnabled:true];
    [settings setDepthDataFiltered:true];
    [settings setPhotoQualityPrioritization:AVCapturePhotoQualityPrioritizationBalanced];
    
    [self.stillImageOutput capturePhotoWithSettings:settings delegate:self];
    [[self.previewLayer connection] setEnabled:NO];
    
}

- (void)recordWithOrientation:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject{
    [self.sensorOrientationChecker getDeviceOrientationWithBlock:^(UIInterfaceOrientation orientation) {
        NSMutableDictionary *tmpOptions = [options mutableCopy];
        if ([tmpOptions valueForKey:@"orientation"] == nil) {
            tmpOptions[@"orientation"] = [NSNumber numberWithInteger:[self.sensorOrientationChecker convertToAVCaptureVideoOrientation: orientation]];
        }
        self.deviceOrientation = [NSNumber numberWithInteger:orientation];
        self.orientation = [NSNumber numberWithInteger:[tmpOptions[@"orientation"] integerValue]];
        [self record:tmpOptions resolve:resolve reject:reject];
    }];
}
- (void)record:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
    if(self.videoCaptureDeviceInput == nil || !self.session.isRunning){
        reject(@"E_VIDEO_CAPTURE_FAILED", @"Camera is not ready.", nil);
        return;
    }

    if (!self.deviceOrientation) {
        [self recordWithOrientation:options resolve:resolve reject:reject];
        return;
    }

    NSInteger orientation = [options[@"orientation"] integerValue];

    // some operations will change our config
    // so we batch config updates, even if inner calls
    // might also call this, only the outermost commit will take effect
    // making the camera changes much faster.
    [self.session beginConfiguration];


    if (_movieFileOutput == nil) {
        // At the time of writing AVCaptureMovieFileOutput and AVCaptureVideoDataOutput (> GMVDataOutput)
        // cannot coexist on the same AVSession (see: https://stackoverflow.com/a/4986032/1123156).
        // We stop face detection here and restart it in when AVCaptureMovieFileOutput finishes recording.
        if ([self.textDetector isRealDetector]) {
            [self stopTextRecognition];
        }
        if ([self.faceDetector isRealDetector]) {
            [self stopFaceDetection];
        }
        if ([self.barcodeDetector isRealDetector]) {
            [self stopBarcodeDetection];
        }
        [self setupMovieFileCapture];
    }

    if (self.movieFileOutput == nil || self.movieFileOutput.isRecording || _videoRecordedResolve != nil || _videoRecordedReject != nil) {
        [self.session commitConfiguration];
      return;
    }

    [self updateSessionPreset:[self getDefaultPreset]];


    AVCaptureConnection *connection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];

    if (self.videoStabilizationMode != 0) {
        if (connection.isVideoStabilizationSupported == NO) {
            RCTLogWarn(@"%s: Video Stabilization is not supported on this device.", __func__);
        } else {
            [connection setPreferredVideoStabilizationMode:self.videoStabilizationMode];
        }
    }
    [connection setVideoOrientation:orientation];

    BOOL recordAudio = [options valueForKey:@"mute"] == nil || ([options valueForKey:@"mute"] != nil && ![options[@"mute"] boolValue]);

    // sound recording connection, we can easily turn it on/off without manipulating inputs, this prevents flickering.
    // note that mute will also be set to true
    // if captureAudio is set to false on the JS side.
    // Check the property anyways just in case it is manipulated
    // with setNativeProps
    if(recordAudio && self.captureAudio){

        // if we haven't initialized our capture session yet
        // initialize it. This will cause video to flicker.
        [self initializeAudioCaptureSessionInput];


        // finally, make sure we got access to the capture device
        // and turn the connection on.
        if(self.audioCaptureDeviceInput != nil){
            AVCaptureConnection *audioConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeAudio];
            audioConnection.enabled = YES;
        }

    }

    // if we have a capture input but are muted
    // disable connection. No flickering here.
    else if(self.audioCaptureDeviceInput != nil){
        AVCaptureConnection *audioConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeAudio];
         audioConnection.enabled = NO;
    }

    dispatch_async(self.sessionQueue, ^{

        // session preset might affect this, so we run this code
        // also in the session queue

        if (options[@"maxDuration"]) {
            Float64 maxDuration = [options[@"maxDuration"] floatValue];
            self.movieFileOutput.maxRecordedDuration = CMTimeMakeWithSeconds(maxDuration, 30);
        }

        if (options[@"maxFileSize"]) {
            self.movieFileOutput.maxRecordedFileSize = [options[@"maxFileSize"] integerValue];
        }

        if (options[@"fps"]) {
            AVCaptureDevice *device = [self.videoCaptureDeviceInput device];
            AVCaptureDeviceFormat *activeFormat = device.activeFormat;
            CMFormatDescriptionRef activeDescription = activeFormat.formatDescription;
            CMVideoDimensions activeDimensions = CMVideoFormatDescriptionGetDimensions(activeDescription);

            NSInteger fps = [options[@"fps"] integerValue];
            CGFloat desiredFPS = (CGFloat)fps;

            AVCaptureDeviceFormat *selectedFormat = nil;
            int32_t activeWidth = activeDimensions.width;
            int32_t maxWidth = 0;

            for (AVCaptureDeviceFormat *format in [device formats]) {
                CMFormatDescriptionRef formatDescription = format.formatDescription;
                CMVideoDimensions formatDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                int32_t formatWidth = formatDimensions.width;
                if (formatWidth != activeWidth || formatWidth < maxWidth) {
                    continue;
                }

                for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
                    if (range.minFrameRate <= desiredFPS && desiredFPS <= range.maxFrameRate) {
                        selectedFormat = format;
                        maxWidth = formatWidth;
                    }
                }
            }

            if (selectedFormat) {
                if ([device lockForConfiguration:nil]) {
                    device.activeFormat = selectedFormat;
                    device.activeVideoMinFrameDuration = CMTimeMake(1, (int32_t)desiredFPS);
                    device.activeVideoMaxFrameDuration = CMTimeMake(1, (int32_t)desiredFPS);
                    [device unlockForConfiguration];
                }
            } else {
                RCTLog(@"We could not find a suitable format for this device.");
            }
        }

        if (options[@"codec"]) {
            if (@available(iOS 10, *)) {
                AVVideoCodecType videoCodecType = options[@"codec"];
                if ([self.movieFileOutput.availableVideoCodecTypes containsObject:videoCodecType]) {
                    self.videoCodecType = videoCodecType;
                    if(options[@"videoBitrate"]) {
                        NSString *videoBitrate = options[@"videoBitrate"];
                        [self.movieFileOutput setOutputSettings:@{
                          AVVideoCodecKey:videoCodecType,
                          AVVideoCompressionPropertiesKey:
                              @{
                                  AVVideoAverageBitRateKey:videoBitrate
                              }
                          } forConnection:connection];
                    } else {
                        [self.movieFileOutput setOutputSettings:@{AVVideoCodecKey:videoCodecType} forConnection:connection];
                    }
                } else {
                    RCTLogWarn(@"Video Codec %@ is not available.", videoCodecType);
                }
            }
            else {
                RCTLogWarn(@"%s: Setting videoCodec is only supported above iOS version 10.", __func__);
            }
        }

        NSString *path = nil;
        if (options[@"path"]) {
            path = options[@"path"];
        }
        else {
            path = [RNFileSystem generatePathInDirectory:[[RNFileSystem cacheDirectoryPath] stringByAppendingPathComponent:@"Camera"] withExtension:@".mov"];
        }

        if ([options[@"mirrorVideo"] boolValue]) {
            if ([connection isVideoMirroringSupported]) {
                [connection setAutomaticallyAdjustsVideoMirroring:NO];
                [connection setVideoMirrored:YES];
            }
        }

        // finally, commit our config changes before starting to record
        [self.session commitConfiguration];

        // and update flash in case it was turned off automatically
        // due to session/preset changes
        [self updateFlashMode];

        // after everything is set, start recording with a tiny delay
        // to ensure the camera already has focus and exposure set.
        double delayInSeconds = 0.5;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);

        // we will use this flag to stop recording
        // if it was requested to stop before it could even start
        _recordRequested = YES;

        dispatch_after(popTime, self.sessionQueue, ^(void){

            // our session might have stopped in between the timeout
            // so make sure it is still valid, otherwise, error and cleanup
            if(self.movieFileOutput != nil && self.videoCaptureDeviceInput != nil && _recordRequested){
                NSURL *outputURL = [[NSURL alloc] initFileURLWithPath:path];
                [self.movieFileOutput startRecordingToOutputFileURL:outputURL recordingDelegate:self];
                self.videoRecordedResolve = resolve;
                self.videoRecordedReject = reject;

                [self onRecordingStart:@{
                    @"uri": outputURL.absoluteString,
                    @"videoOrientation": @([self.orientation integerValue]),
                    @"deviceOrientation": @([self.deviceOrientation integerValue])
                }];

            }
            else{
                reject(@"E_VIDEO_CAPTURE_FAILED", !_recordRequested ? @"Recording request cancelled." : @"Camera is not ready.", nil);
                [self cleanupCamera];
            }

            // reset our flag
            _recordRequested = NO;
        });


    });
}

- (void)stopRecording
{
    dispatch_async(self.sessionQueue, ^{
        if ([self.movieFileOutput isRecording]) {
            [self.movieFileOutput stopRecording];
            [self onRecordingEnd:@{}];
        } else {
            if(_recordRequested){
                _recordRequested = NO;
            }
            else{
                RCTLogWarn(@"Video is not recording.");
            }
        }
    });
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
        [[stillImageOutput connectionWithMediaType:AVMediaTypeVideo ] setVideoOrientation:AVCaptureVideoOrientationPortrait];

        [self.session setSessionPreset:AVCaptureSessionPreset1280x720];
        if ([self.session canAddOutput:stillImageOutput]) {
            [self.session addOutput:stillImageOutput];
            self.stillImageOutput = stillImageOutput;
            [stillImageOutput setDepthDataDeliveryEnabled:YES];

        }
        
        [self setupOrDisableBarcodeScanner];

        _sessionInterrupted = NO;
        [self.session startRunning];
        [self onReady:nil];
    });
}

- (void)stopSession
{
#if TARGET_IPHONE_SIMULATOR
    return;
#endif
    dispatch_async(self.sessionQueue, ^{
        if ([self.textDetector isRealDetector]) {
            [self stopTextRecognition];
        }
        if ([self.faceDetector isRealDetector]) {
            [self stopFaceDetection];
        }
        if ([self.barcodeDetector isRealDetector]) {
            [self stopBarcodeDetection];
        }
        [self.previewLayer removeFromSuperlayer];
        [self.session commitConfiguration];
        [self.session stopRunning];

        for (AVCaptureInput *input in self.session.inputs) {
            [self.session removeInput:input];
        }

        for (AVCaptureOutput *output in self.session.outputs) {
            [self.session removeOutput:output];
        }

        // cleanup audio input if any, and release
        // audio session so other apps can continue playback.
        [self removeAudioCaptureSessionInput];

        // clean these up as well since we've removed
        // all inputs and outputs from session
        self.videoCaptureDeviceInput = nil;
        self.audioCaptureDeviceInput = nil;
        self.movieFileOutput = nil;
    });
}

// Initializes audio capture device
// Note: Ensure this is called within a a session configuration block
- (void)initializeAudioCaptureSessionInput
{
    // only initialize if not initialized already
    if(self.audioCaptureDeviceInput == nil){
        NSError *error = nil;

        AVCaptureDevice *audioCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioCaptureDevice error:&error];

        if (error || audioDeviceInput == nil) {
            RCTLogWarn(@"%s: %@", __func__, error);
        }

        else{

            // test if we can activate the device input.
            // If we fail, means it is already being used
            BOOL setActive = [[AVAudioSession sharedInstance] setActive:YES error:&error];

            if (!setActive) {
                RCTLogWarn(@"Audio device could not set active: %s: %@", __func__, error);
            }

            else if ([self.session canAddInput:audioDeviceInput]) {
                [self.session addInput:audioDeviceInput];
                self.audioCaptureDeviceInput = audioDeviceInput;

                // inform that audio has been resumed
                if(self.onAudioConnected){
                    self.onAudioConnected(nil);
                }
            }
            else{
                RCTLog(@"Cannot add audio input");
            }
        }

        // if we failed to get the audio device, fire our interrupted event
        if(self.audioCaptureDeviceInput == nil && self.onAudioInterrupted){
            self.onAudioInterrupted(nil);
        }
    }
}


// Removes audio capture from the session, allowing the session
// to resume if it was interrupted, and stopping any
// recording in progress with the appropriate flags.
- (void)removeAudioCaptureSessionInput
{
    if(self.audioCaptureDeviceInput != nil){

        BOOL audioRemoved = NO;

        if ([self.session.inputs containsObject:self.audioCaptureDeviceInput]) {

            if ([self isRecording]) {
                self.isRecordingInterrupted = YES;
            }

            [self.session removeInput:self.audioCaptureDeviceInput];

            self.audioCaptureDeviceInput = nil;

            // update flash since it gets reset when
            // we change the session inputs
            dispatch_async(self.sessionQueue, ^{
                [self updateFlashMode];
            });

            audioRemoved = YES;
        }

        // Deactivate our audio session so other audio can resume
        // playing, if any. E.g., background music.
        // unless told not to
        if(!self.keepAudioSession){
            NSError *error = nil;

            BOOL setInactive = [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];

            if (!setInactive) {
                RCTLogWarn(@"Audio device could not set inactive: %s: %@", __func__, error);
            }
        }

        self.audioCaptureDeviceInput = nil;

        // inform that audio was interrupted
        if(audioRemoved && self.onAudioInterrupted){
            self.onAudioInterrupted(nil);
        }
    }
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


        // if we have not yet set our audio capture device,
        // set it. Setting it early will prevent flickering when
        // recording a video
        // Only set it if captureAudio is true so we don't prompt
        // for permission if audio is not needed.
        // TODO: If we can update checkRecordAudioAuthorizationStatus
        // to actually do something in production, we can replace
        // the captureAudio prop by a simple permission check;
        // for example, checking
        // [[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted
        if(self.captureAudio){
            [self initializeAudioCaptureSessionInput];
        }

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
        if (self.canDetectFaces && [preset isEqual:AVCaptureSessionPresetPhoto]) {
            RCTLog(@"AVCaptureSessionPresetPhoto not supported during face detection. Falling back to AVCaptureSessionPresetHigh");
            preset = AVCaptureSessionPresetHigh;
        }
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
// after disabling audio.
- (void)audioDidInterrupted:(NSNotification *)notification
{
    NSDictionary *userInfo = notification.userInfo;
    NSInteger type = [[userInfo valueForKey:AVAudioSessionInterruptionTypeKey] integerValue];


    // if our audio interruption ended
    if(type == AVAudioSessionInterruptionTypeEnded){

        // and the end event contains a hint that we should resume
        // audio. Then re-connect our audio session if we are
        // capturing audio.
        // Sometimes we are hinted to not resume audio; e.g.,
        // when playing music in background.

        NSInteger option = [[userInfo valueForKey:AVAudioSessionInterruptionOptionKey] integerValue];

        if(self.captureAudio && option == AVAudioSessionInterruptionOptionShouldResume){

            dispatch_async(self.sessionQueue, ^{

                // initialize audio if we need it
                // check again captureAudio in case it was changed
                // in between
                if(self.captureAudio){
                    [self initializeAudioCaptureSessionInput];
                }
            });
        }

    }
}


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

    if(type == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient){
        // if we have audio, stop it so preview resumes
        // it will eventually be re-loaded the next time recording
        // is requested, although it will flicker.
        dispatch_async(self.sessionQueue, ^{
            [self removeAudioCaptureSessionInput];
        });

    }

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

    if ([self.textDetector isRealDetector] || [self.faceDetector isRealDetector]) {
        [self cleanupMovieFileCapture];
    }

    if ([self.textDetector isRealDetector]) {
        [self setupOrDisableTextDetector];
    }

    if ([self.faceDetector isRealDetector]) {
        [self setupOrDisableFaceDetector];
    }

    if ([self.barcodeDetector isRealDetector]) {
        [self setupOrDisableBarcodeDetector];
    }

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

# pragma mark - FaceDetectorMlkit

-(id)createFaceDetectorMlKit
{
    Class faceDetectorManagerClassMlkit = NSClassFromString(@"FaceDetectorManagerMlkit");
    return [[faceDetectorManagerClassMlkit alloc] init];
}

- (void)setupOrDisableFaceDetector
{
    [self stopFaceDetection];
}

- (void)stopFaceDetection
{
    if (self.videoDataOutput && !self.canReadText) {
        [self.session removeOutput:self.videoDataOutput];
    }
    self.videoDataOutput = nil;
    AVCaptureSessionPreset preset = [self getDefaultPreset];
    if (self.session.sessionPreset != preset) {
        [self updateSessionPreset: preset];
    }
}

- (void)updateTrackingEnabled:(id)requestedTracking
{
    [self.faceDetector setTracking:requestedTracking queue:self.sessionQueue];
}

- (void)updateFaceDetectionMode:(id)requestedMode
{
    [self.faceDetector setPerformanceMode:requestedMode queue:self.sessionQueue];
}

- (void)updateFaceDetectionLandmarks:(id)requestedLandmarks
{
    [self.faceDetector setLandmarksMode:requestedLandmarks queue:self.sessionQueue];
}

- (void)updateFaceDetectionClassifications:(id)requestedClassifications
{
    [self.faceDetector setClassificationMode:requestedClassifications queue:self.sessionQueue];
}

- (void)onFacesDetected:(NSDictionary *)event
{
    if (_onFacesDetected && _session) {
        _onFacesDetected(event);
    }
}

# pragma mark - BarcodeDetectorMlkit

-(id)createBarcodeDetectorMlKit
{
    Class barcodeDetectorManagerClassMlkit = NSClassFromString(@"BarcodeDetectorManagerMlkit");
    return [[barcodeDetectorManagerClassMlkit alloc] init];
}

- (void)setupOrDisableBarcodeDetector
{

    [self stopBarcodeDetection];
}

- (void)stopBarcodeDetection
{
    if (self.videoDataOutput && !self.canReadText) {
        [self.session removeOutput:self.videoDataOutput];
    }
    self.videoDataOutput = nil;
    AVCaptureSessionPreset preset = [self getDefaultPreset];
    if (self.session.sessionPreset != preset) {
        [self updateSessionPreset: preset];
    }
}

- (void)updateGoogleVisionBarcodeType:(id)requestedTypes
{
    [self.barcodeDetector setType:requestedTypes queue:self.sessionQueue];
}

- (void)onBarcodesDetected:(NSDictionary *)event
{
    if (_onGoogleVisionBarcodesDetected && _session) {
        _onGoogleVisionBarcodesDetected(event);
    }
}

# pragma mark - TextDetector

-(id)createTextDetector
{
    Class textDetectorManagerClass = NSClassFromString(@"TextDetectorManager");
    return [[textDetectorManagerClass alloc] init];
}

- (void)setupOrDisableTextDetector
{
    if ([self canReadText] && [self.textDetector isRealDetector]){
        if (!self.videoDataOutput) {
            self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
            if (![self.session canAddOutput:_videoDataOutput]) {
                NSLog(@"Failed to setup video data output");
                [self stopTextRecognition];
                return;
            }
            NSDictionary *rgbOutputSettings = [NSDictionary
                dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA]
                                forKey:(id)kCVPixelBufferPixelFormatTypeKey];
            [self.videoDataOutput setVideoSettings:rgbOutputSettings];
            [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
            [self.videoDataOutput setSampleBufferDelegate:self queue:self.sessionQueue];
            [self.session addOutput:_videoDataOutput];
        }
    } else {
        [self stopTextRecognition];
    }
}

- (void)stopTextRecognition
{
    if (self.videoDataOutput && !self.canDetectFaces) {
        [self.session removeOutput:self.videoDataOutput];
    }
    self.videoDataOutput = nil;
}

# pragma mark - mlkit

- (void)captureOutput:(AVCaptureOutput *)captureOutput
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection
{
    if (![self.textDetector isRealDetector] && ![self.faceDetector isRealDetector] && ![self.barcodeDetector isRealDetector]) {
        NSLog(@"failing real check");
        return;
    }

    // Do not submit image for text/face recognition too often:
    // 1. we only dispatch events every 500ms anyway
    // 2. wait until previous recognition is finished
    // 3. let user disable text recognition, e.g. onTextRecognized={someCondition ? null : this.textRecognized}
    NSDate *methodFinish = [NSDate date];
    NSTimeInterval timePassedSinceSubmittingForText = [methodFinish timeIntervalSinceDate:self.startText];
    NSTimeInterval timePassedSinceSubmittingForFace = [methodFinish timeIntervalSinceDate:self.startFace];
    NSTimeInterval timePassedSinceSubmittingForBarcode = [methodFinish timeIntervalSinceDate:self.startBarcode];
    BOOL canSubmitForTextDetection = timePassedSinceSubmittingForText > 0.5 && _finishedReadingText && self.canReadText && [self.textDetector isRealDetector];
    BOOL canSubmitForFaceDetection = timePassedSinceSubmittingForFace > 0.5 && _finishedDetectingFace && self.canDetectFaces && [self.faceDetector isRealDetector];
    BOOL canSubmitForBarcodeDetection = timePassedSinceSubmittingForBarcode > 0.5 && _finishedDetectingBarcodes && self.canDetectBarcodes && [self.barcodeDetector isRealDetector];
    if (canSubmitForFaceDetection || canSubmitForTextDetection || canSubmitForBarcodeDetection) {
        CGSize previewSize = CGSizeMake(_previewLayer.frame.size.width, _previewLayer.frame.size.height);
        NSInteger position = self.videoCaptureDeviceInput.device.position;
        UIImage *image = [RNCameraUtils convertBufferToUIImage:sampleBuffer previewSize:previewSize position:position];
        // take care of the fact that preview dimensions differ from the ones of the image that we submit for text detection
        float scaleX = _previewLayer.frame.size.width / image.size.width;
        float scaleY = _previewLayer.frame.size.height / image.size.height;

        // find text features
        if (canSubmitForTextDetection) {
            _finishedReadingText = false;
            self.startText = [NSDate date];
            [self.textDetector findTextBlocksInFrame:image scaleX:scaleX scaleY:scaleY completed:^(NSArray * textBlocks) {
                NSDictionary *eventText = @{@"type" : @"TextBlock", @"textBlocks" : textBlocks};
                [self onText:eventText];
                self.finishedReadingText = true;
            }];
        }
        // find face features
        if (canSubmitForFaceDetection) {
            _finishedDetectingFace = false;
            self.startFace = [NSDate date];
            [self.faceDetector findFacesInFrame:image scaleX:scaleX scaleY:scaleY completed:^(NSArray * faces) {
                NSDictionary *eventFace = @{@"type" : @"face", @"faces" : faces};
                [self onFacesDetected:eventFace];
                self.finishedDetectingFace = true;
            }];
        }
        // find barcodes
        if (canSubmitForBarcodeDetection) {
            _finishedDetectingBarcodes = false;
            self.startBarcode = [NSDate date];
            [self.barcodeDetector findBarcodesInFrame:image scaleX:scaleX scaleY:scaleY completed:^(NSArray * barcodes) {
                NSDictionary *eventBarcode = @{@"type" : @"barcode", @"barcodes" : barcodes};
                [self onBarcodesDetected:eventBarcode];
                self.finishedDetectingBarcodes = true;
            }];
        }
    }
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
    return [[CIImage alloc] initWithCVImageBuffer:[matte mattingImage] options:@{
        /*kCIImageAuxiliarySemanticSegmentationSkinMatte: [NSNumber numberWithBool: ssmType == AVSemanticSegmentationMatteTypeSkin ],
        kCIImageAuxiliarySemanticSegmentationHairMatte: [NSNumber numberWithBool: ssmType == AVSemanticSegmentationMatteTypeHair ],
        kCIImageColorSpace: [NSNumber numberWithInt:CGColorSpaceCreateWithName(kCGColorSpaceSRGB)]*/
    }];
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
    
    CGImageRef *orientedImage = CGBitmapContextCreateImage(contextRef);
    
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
    
    CGImageRef *orientedImage = CGBitmapContextCreateImage(contextRef);
    
    return orientedImage;
}


- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    [self recognizeFacialLandmarks:photo];
    output.depthDataDeliveryEnabled = true;
    NSMutableArray<NSData *> *semanticSegmentationMatteDataArray = [[NSMutableArray alloc] init];
    NSURL *photoFileName = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:@"photo.jpg"];
    CGImageRef image = [photo CGImageRepresentation];
    CGImageRef newImage = [self rotateImage:image];

    struct CGImageDestination *destination = CGImageDestinationCreateWithURL(CFBridgingRetain(photoFileName), kUTTypeJPEG, 1, nil);
    CGImageDestinationAddImage(destination, newImage, nil);
    CGImageDestinationFinalize(destination);
    
    NSString *payload = [NSString stringWithFormat:@"%@,%d,%d", [photoFileName absoluteString], self.width, self.height];
    _onPhoto(@{@"photo":payload});

    for (id matteType in [output enabledSemanticSegmentationMatteTypes]) {
        CIImage *img = [self handleMatteData:photo matteType:matteType];
        CGSize dim = CGSizeMake(720, 1080);
        // TODO: Resize
        CIContext *context = [[CIContext alloc] init];
        
        CGImageRef matte = [context createCGImage:img fromRect:[img extent]];
        CGImageRef resizedMatte = [self resizeImage:[self rotateImage:matte]];
        
        NSURL *matteFileName = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[NSString stringWithFormat:@"matte-%@.jpg", matteType]];
        struct CGImageDestination *matteDestination = CGImageDestinationCreateWithURL(CFBridgingRetain(matteFileName), kUTTypeJPEG, 1, nil);

        CGImageDestinationAddImage(matteDestination, resizedMatte, nil);
        CGImageDestinationFinalize(matteDestination);
        
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
