#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "CameraFocusSquare.h"

@class RCTDepthCameraManager;

@interface RCTDepthCamera : UIView

- (id)initWithManager:(RCTDepthCameraManager*)manager bridge:(RCTBridge *)bridge;

@property (nonatomic, strong) RCTCameraFocusSquare *camFocus;
@end
