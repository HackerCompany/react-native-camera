package com.hacker.depthcamera;

import com.facebook.react.bridge.*;


public class CameraModule extends ReactContextBaseJavaModule {
  private static final String TAG = "CameraModule";

  public CameraModule(ReactApplicationContext reactContext) {
    super(reactContext);
  }


  @Override
  public String getName() {
    return "RNDepthCameraModule";
  }



}
