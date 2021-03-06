#import "RNDepthCamera.h"
#import "RNDepthCameraManager.h"
#import "RNDepthFileSystem.h"
#import "RNDepthImageUtils.h"
#import <React/RCTBridge.h>
#import <React/RCTUIManager.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <React/UIView+React.h>
#import <CoreServices/CoreServices.h>


@implementation RNDepthCameraManager

RCT_EXPORT_MODULE(RNDepthCameraManager);
RCT_EXPORT_VIEW_PROPERTY(onCameraReady, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onMountError, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onPictureTaken, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onPictureSaved, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onRecordingStart, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onRecordingEnd, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onTextRecognized, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(onSubjectAreaChanged, RCTDirectEventBlock);
RCT_EXPORT_VIEW_PROPERTY(videoStabilizationMode, NSInteger);

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

- (UIView *)view
{
    return [[RNDepthCamera alloc] initWithBridge:self.bridge];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishRecordingLivePhotoMovieForEventualFileAtURL:(NSURL *)outputFileURL resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings  API_AVAILABLE(ios(10.0)){
    self.width = resolvedSettings.photoDimensions.width;
    self.height = resolvedSettings.photoDimensions.height;
}



- (NSDictionary *)constantsToExport
{
    return @{
             @"Type" :
                 @{@"front" : @(RNCameraTypeFront), @"back" : @(RNCameraTypeBack)},
             @"FlashMode" : @{
                     @"off" : @(RNCameraFlashModeOff),
                     @"on" : @(RNCameraFlashModeOn),
                     @"auto" : @(RNCameraFlashModeAuto),
                     @"torch" : @(RNCameraFlashModeTorch)
                     },
             @"AutoFocus" :
                 @{@"on" : @(RNCameraAutoFocusOn), @"off" : @(RNCameraAutoFocusOff)},
             @"WhiteBalance" : @{
                     @"auto" : @(RNCameraWhiteBalanceAuto),
                     @"sunny" : @(RNCameraWhiteBalanceSunny),
                     @"cloudy" : @(RNCameraWhiteBalanceCloudy),
                     @"shadow" : @(RNCameraWhiteBalanceShadow),
                     @"incandescent" : @(RNCameraWhiteBalanceIncandescent),
                     @"fluorescent" : @(RNCameraWhiteBalanceFluorescent)
                     },
             @"VideoQuality": @{
                     @"2160p": @(RNCameraVideo2160p),
                     @"1080p": @(RNCameraVideo1080p),
                     @"720p": @(RNCameraVideo720p),
                     @"480p": @(RNCameraVideo4x3),
                     @"4:3": @(RNCameraVideo4x3),
                     @"288p": @(RNCameraVideo288p),
                     },
             @"Orientation": @{
                     @"auto": @(RNCameraOrientationAuto),
                     @"landscapeLeft": @(RNCameraOrientationLandscapeLeft),
                     @"landscapeRight": @(RNCameraOrientationLandscapeRight),
                     @"portrait": @(RNCameraOrientationPortrait),
                     @"portraitUpsideDown": @(RNCameraOrientationPortraitUpsideDown)
                     },
             @"VideoCodec": [[self class] validCodecTypes],
             @"BarCodeType" : [[self class] validBarCodeTypes],
             @"FaceDetection" : [[self class] faceDetectorConstants],
             @"VideoStabilization": [[self class] validVideoStabilizationModes],
             @"GoogleVisionBarcodeDetection": @{
                 @"BarcodeType": [[self class] barcodeDetectorConstants],
             }
             };
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"onCameraReady", @"onMountError", @"onBarCodeRead", @"onFacesDetected", @"onPictureTaken", @"onPictureSaved", @"onRecordingStart", @"onRecordingEnd", @"onTextRecognized", @"onGoogleVisionBarcodesDetected", @"onSubjectAreaChanged", @"onLandmarks", @"onMatte"];
}

+ (NSDictionary *)validCodecTypes
{
    if (@available(iOS 11, *)) {
        return @{
                 @"H264": AVVideoCodecTypeH264,
                 @"HVEC": AVVideoCodecTypeHEVC,
                 @"JPEG": AVVideoCodecTypeJPEG,
                 @"AppleProRes422": AVVideoCodecTypeAppleProRes422,
                 @"AppleProRes4444": AVVideoCodecTypeAppleProRes4444
                 };
    } else {
        return @{
                 @"H264": AVVideoCodecH264,
                 @"JPEG": AVVideoCodecJPEG
                 };
    }
}

+ (NSDictionary *)validVideoStabilizationModes
{
    return @{
             @"off": @(AVCaptureVideoStabilizationModeOff),
             @"standard": @(AVCaptureVideoStabilizationModeStandard),
             @"cinematic": @(AVCaptureVideoStabilizationModeCinematic),
             @"auto": @(AVCaptureVideoStabilizationModeAuto)
             };
}

+ (NSDictionary *)validBarCodeTypes
{
    return @{
             @"upc_e" : AVMetadataObjectTypeUPCECode,
             @"code39" : AVMetadataObjectTypeCode39Code,
             @"code39mod43" : AVMetadataObjectTypeCode39Mod43Code,
             @"ean13" : AVMetadataObjectTypeEAN13Code,
             @"ean8" : AVMetadataObjectTypeEAN8Code,
             @"code93" : AVMetadataObjectTypeCode93Code,
             @"code128" : AVMetadataObjectTypeCode128Code,
             @"pdf417" : AVMetadataObjectTypePDF417Code,
             @"qr" : AVMetadataObjectTypeQRCode,
             @"aztec" : AVMetadataObjectTypeAztecCode,
             @"interleaved2of5" : AVMetadataObjectTypeInterleaved2of5Code,
             @"itf14" : AVMetadataObjectTypeITF14Code,
             @"datamatrix" : AVMetadataObjectTypeDataMatrixCode
             };
}

+ (NSDictionary *)pictureSizes
{
    return @{
             @"3840x2160" : AVCaptureSessionPreset3840x2160,
             @"1920x1080" : AVCaptureSessionPreset1920x1080,
             @"1280x720" : AVCaptureSessionPreset1280x720,
             @"640x480" : AVCaptureSessionPreset640x480,
             @"352x288" : AVCaptureSessionPreset352x288,
             @"Photo" : AVCaptureSessionPresetPhoto,
             @"High" : AVCaptureSessionPresetHigh,
             @"Medium" : AVCaptureSessionPresetMedium,
             @"Low" : AVCaptureSessionPresetLow,
             @"None": @(-1),
             };
}

+ (NSDictionary *)faceDetectorConstants
{
#if __has_include(<FirebaseMLVision/FirebaseMLVision.h>)
    return [DepthFaceDetectorManagerMlkit constants];
#else
    return [NSDictionary new];
#endif
}

+ (NSDictionary *)barcodeDetectorConstants
{
#if __has_include(<FirebaseMLVision/FirebaseMLVision.h>)
    return [DepthBarcodeDetectorManagerMlkit constants];
#else
    return [NSDictionary new];
#endif
}

RCT_CUSTOM_VIEW_PROPERTY(type, NSInteger, RNDepthCamera)
{
    NSInteger newType = [RCTConvert NSInteger:json];
    if (view.presetCamera != newType) {
        [view setPresetCamera:newType];
        [view updateType];
    }
}

RCT_CUSTOM_VIEW_PROPERTY(cameraId, NSString, RNDepthCamera)
{
    NSString *newId = [RCTConvert NSString:json];

    // also compare pointers so we check for nulls
    if (view.cameraId != newId && ![view.cameraId isEqualToString:newId]) {
        [view setCameraId:newId];
        // using same call as setting the type here since they
        // both require the same updates
        [view updateType];
    }
}

RCT_CUSTOM_VIEW_PROPERTY(flashMode, NSInteger, RNDepthCamera)
{
    [view setFlashMode:[RCTConvert NSInteger:json]];
    [view updateFlashMode];
}

RCT_CUSTOM_VIEW_PROPERTY(autoFocus, NSInteger, RNDepthCamera)
{
    [view setAutoFocus:[RCTConvert NSInteger:json]];
    [view updateFocusMode];
}

RCT_CUSTOM_VIEW_PROPERTY(autoFocusPointOfInterest, NSDictionary, RNDepthCamera)
{
    [view setAutoFocusPointOfInterest:[RCTConvert NSDictionary:json]];
    [view updateAutoFocusPointOfInterest];
}

RCT_CUSTOM_VIEW_PROPERTY(focusDepth, NSNumber, RNDepthCamera)
{
    [view setFocusDepth:[RCTConvert float:json]];
    [view updateFocusDepth];
}

RCT_CUSTOM_VIEW_PROPERTY(useNativeZoom, BOOL, RNDepthCamera)
{
    view.useNativeZoom=[RCTConvert BOOL:json];
    [view setupOrDisablePinchZoom];
}

RCT_CUSTOM_VIEW_PROPERTY(zoom, NSNumber, RNDepthCamera)
{
    [view setZoom:[RCTConvert CGFloat:json]];
    [view updateZoom];
}

RCT_CUSTOM_VIEW_PROPERTY(maxZoom, NSNumber, RNDepthCamera)
{
    [view setMaxZoom:[RCTConvert CGFloat:json]];
    [view updateZoom];
}

RCT_CUSTOM_VIEW_PROPERTY(whiteBalance, NSInteger, RNDepthCamera)
{
    [view setWhiteBalance:[RCTConvert NSInteger:json]];
    [view updateWhiteBalance];
}

RCT_CUSTOM_VIEW_PROPERTY(exposure, NSNumber, RNDepthCamera)
{
    [view setExposure:[RCTConvert float:json]];
    [view updateExposure];
}

RCT_CUSTOM_VIEW_PROPERTY(pictureSize, NSString *, RNDepthCamera)
{
    [view setPictureSize:[[self class] pictureSizes][[RCTConvert NSString:json]]];
    [view updatePictureSize];
}


RCT_CUSTOM_VIEW_PROPERTY(barCodeScannerEnabled, BOOL, RNDepthCamera)
{

    view.isReadingBarCodes = [RCTConvert BOOL:json];
    [view setupOrDisableBarcodeScanner];
}

RCT_CUSTOM_VIEW_PROPERTY(barCodeTypes, NSArray, RNDepthCamera)
{
    [view setBarCodeTypes:[RCTConvert NSArray:json]];
}


RCT_CUSTOM_VIEW_PROPERTY(rectOfInterest, CGRect, RNDepthCamera)
{
    [view setRectOfInterest: [RCTConvert CGRect:json]];
    [view updateRectOfInterest];
}

RCT_CUSTOM_VIEW_PROPERTY(defaultVideoQuality, NSInteger, RNDepthCamera)
{
    [view setDefaultVideoQuality: [NSNumber numberWithInteger:[RCTConvert NSInteger:json]]];
}

RCT_REMAP_METHOD(takePicture,
                 options:(NSDictionary *)options
                 reactTag:(nonnull NSNumber *)reactTag
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNDepthCamera *> *viewRegistry) {
        RNDepthCamera *view = viewRegistry[reactTag];
        if (![view isKindOfClass:[RNDepthCamera class]]) {
            RCTLogError(@"Invalid view returned from registry, expecting RNDepthCamera, got: %@", view);
        } else {
#if TARGET_IPHONE_SIMULATOR

            NSMutableDictionary *response = [[NSMutableDictionary alloc] init];

            float quality = [options[@"quality"] floatValue];

            NSString *path = nil;

            if (options[@"path"]) {
                path = options[@"path"];
            }
            else{
                path = [RNDepthFileSystem generatePathInDirectory:[[RNDepthFileSystem cacheDirectoryPath] stringByAppendingPathComponent:@"Camera"] withExtension:@".jpg"];
            }
            UIImage *generatedPhoto = [RNDepthImageUtils generatePhotoOfSize:CGSizeMake(200, 200)];
            BOOL useFastMode = options[@"fastMode"] && [options[@"fastMode"] boolValue];
            if (useFastMode) {
                resolve(nil);
            }

            [view onPictureTaken:@{}];

            NSData *photoData = UIImageJPEGRepresentation(generatedPhoto, quality);
            if (![options[@"doNotSave"] boolValue]) {
                response[@"uri"] = [RNDepthImageUtils writeImage:photoData toPath:path];
            }
            response[@"width"] = @(generatedPhoto.size.width);
            response[@"height"] = @(generatedPhoto.size.height);
            if ([options[@"base64"] boolValue]) {
                response[@"base64"] = [photoData base64EncodedStringWithOptions:0];
            }
            if (useFastMode) {
                [view onPictureSaved:@{@"data": response, @"id": options[@"id"]}];
            } else {
                resolve(response);
            }
#else
            [view takePicture:options resolve:resolve reject:reject];
#endif
        }
    }];
}

RCT_EXPORT_METHOD(resumePreview:(nonnull NSNumber *)reactTag)
{
#if TARGET_IPHONE_SIMULATOR
    return;
#endif
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNDepthCamera *> *viewRegistry) {
        RNDepthCamera *view = viewRegistry[reactTag];
        if (![view isKindOfClass:[RNDepthCamera class]]) {
            RCTLogError(@"Invalid view returned from registry, expecting RNDepthCamera, got: %@", view);
        } else {
            [view resumePreview];
        }
    }];
}

RCT_EXPORT_METHOD(pausePreview:(nonnull NSNumber *)reactTag)
{
#if TARGET_IPHONE_SIMULATOR
    return;
#endif
    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNDepthCamera *> *viewRegistry) {
        RNDepthCamera *view = viewRegistry[reactTag];
        if (![view isKindOfClass:[RNDepthCamera class]]) {
            RCTLogError(@"Invalid view returned from registry, expecting RNDepthCamera, got: %@", view);
        } else {
            [view pausePreview];
        }
    }];
}


RCT_EXPORT_METHOD(checkDeviceAuthorizationStatus:(RCTPromiseResolveBlock)resolve
                  reject:(__unused RCTPromiseRejectBlock)reject) {
    __block NSString *mediaType = AVMediaTypeVideo;

    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        if (!granted) {
            resolve(@(granted));
        }
        else {
            mediaType = AVMediaTypeAudio;
            [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
                resolve(@(granted));
            }];
        }
    }];
}

RCT_EXPORT_METHOD(checkVideoAuthorizationStatus:(RCTPromiseResolveBlock)resolve
                  reject:(__unused RCTPromiseRejectBlock)reject) {
#ifdef DEBUG
    if ([[NSBundle mainBundle].infoDictionary objectForKey:@"NSCameraUsageDescription"] == nil) {
        RCTLogWarn(@"Checking video permissions without having key 'NSCameraUsageDescription' defined in your Info.plist. If you do not add it your app will crash when being built in release mode. You will have to add it to your Info.plist file, otherwise RNDepthCamera is not allowed to use the camera.  You can learn more about adding permissions here: https://stackoverflow.com/a/38498347/4202031");
        resolve(@(NO));
        return;
    }
#endif
    __block NSString *mediaType = AVMediaTypeVideo;
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        resolve(@(granted));
    }];
}

RCT_EXPORT_METHOD(checkRecordAudioAuthorizationStatus:(RCTPromiseResolveBlock)resolve
                  reject:(__unused RCTPromiseRejectBlock)reject) {
    if ([[NSBundle mainBundle].infoDictionary objectForKey:@"NSMicrophoneUsageDescription"] == nil) {
        RCTLogWarn(@"Checking audio permissions without having key 'NSMicrophoneUsageDescription' defined in your Info.plist. Audio Recording for your video files is therefore disabled. If you do not need audio on your recordings is is recommended to set the 'captureAudio' property on your component instance to 'false', otherwise you will have to add the key 'NSMicrophoneUsageDescription' to your Info.plist. If you do not your app will crash when being built in release mode. You can learn more about adding permissions here: https://stackoverflow.com/a/38498347/4202031");
        resolve(@(NO));
        return;
    } else {
#ifdef DEBUG
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            resolve(@(granted));
        }];
#else
        resolve(@(YES));
#endif
    }
}

RCT_REMAP_METHOD(getAvailablePictureSizes,
                 ratio:(NSString *)ratio
                 reactTag:(nonnull NSNumber *)reactTag
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve([[[self class] pictureSizes] allKeys]);
}

RCT_EXPORT_METHOD(isRecording:(nonnull NSNumber *)reactTag
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    #if TARGET_IPHONE_SIMULATOR
        reject(@"E_IS_RECORDING_FAILED", @"Video recording is not supported on a simulator.", nil);
        return;
    #endif
        [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, RNDepthCamera *> *viewRegistry) {
            RNDepthCamera *view = viewRegistry[reactTag];
            if (![view isKindOfClass:[RNDepthCamera class]]) {
                RCTLogError(@"Invalid view returned from registry, expecting RNDepthCamera, got: %@", view);
            } else {
                resolve(@([view isRecording]));
            }
        }];
}

RCT_EXPORT_METHOD(getCameraIds:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {

#if TARGET_IPHONE_SIMULATOR
    resolve(@[]);
    return;
#endif

    NSMutableArray *res = [NSMutableArray array];


    // need to filter/search devices based on iOS version
    // these warnings can be easily seen on XCode
    if (@available(iOS 10.0, *)) {
        NSArray *captureDeviceType;


        if (@available(iOS 13.0, *)) {
            captureDeviceType = @[
                AVCaptureDeviceTypeBuiltInWideAngleCamera,
                AVCaptureDeviceTypeBuiltInTelephotoCamera
                #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
                    ,AVCaptureDeviceTypeBuiltInUltraWideCamera
                #endif
            ];
        }
        else{
            captureDeviceType = @[
                AVCaptureDeviceTypeBuiltInWideAngleCamera,
                AVCaptureDeviceTypeBuiltInTelephotoCamera
            ];
        }


        AVCaptureDeviceDiscoverySession *captureDevice =
        [AVCaptureDeviceDiscoverySession
         discoverySessionWithDeviceTypes:captureDeviceType
         mediaType:AVMediaTypeVideo
         position:AVCaptureDevicePositionUnspecified];

        for(AVCaptureDevice *camera in [captureDevice devices]){

            // exclude virtual devices. We currently cannot use
            // any virtual device feature like auto switching or
            // depth of field detetion anyways.
            #if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
                if (@available(iOS 13.0, *)) {
                    if([camera isVirtualDevice]){
                        continue;
                    }
                }
            #endif


            if([camera position] == AVCaptureDevicePositionFront) {
                [res addObject: @{
                    @"id": [camera uniqueID],
                    @"type": @(RNCameraTypeFront),
                    @"deviceType": [camera deviceType]
                }];
            }
            else if([camera position] == AVCaptureDevicePositionBack){
                [res addObject: @{
                    @"id": [camera uniqueID],
                    @"type": @(RNCameraTypeBack),
                    @"deviceType": [camera deviceType]
                }];
            }

        }

    } else {
        NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for(AVCaptureDevice *camera in devices) {


            if([camera position] == AVCaptureDevicePositionFront) {
                [res addObject: @{
                    @"id": [camera uniqueID],
                    @"type": @(RNCameraTypeFront),
                    @"deviceType": @""
                }];
            }
            else if([camera position] == AVCaptureDevicePositionBack){
                [res addObject: @{
                    @"id": [camera uniqueID],
                    @"type": @(RNCameraTypeBack),
                    @"deviceType": @""
                }];
            }

        }
    }

    resolve(res);
}

@end
