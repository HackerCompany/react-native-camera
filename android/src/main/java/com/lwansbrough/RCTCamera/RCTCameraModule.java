/**
 * Created by Fabrice Armisen (farmisen@gmail.com) on 1/4/16.
 * Android video recording support by Marc Johnson (me@marc.mn) 4/2016
 */

package com.lwansbrough.RCTCamera;

import android.hardware.Camera;
import android.media.*;

import com.facebook.react.bridge.LifecycleEventListener;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReadableMap;

import java.io.*;


public class RCTCameraModule extends ReactContextBaseJavaModule
    implements  LifecycleEventListener {
    private static final String TAG = "RCTCameraModule";

    private static ReactApplicationContext _reactContext;

    private MediaRecorder mMediaRecorder;
    private long MRStartTime;
    private File mVideoFile;
    private Camera mCamera = null;
    private Promise mRecordingPromise = null;
    private ReadableMap mRecordingOptions;
    private Boolean mSafeToCapture = true;

    public RCTCameraModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    public static ReactApplicationContext getReactContextSingleton() {
      return _reactContext;
    }


    @Override
    public String getName() {
        return "RCTCameraModule";
    }

    /**
     * LifecycleEventListener overrides
     */
    @Override
    public void onHostResume() {
    }

    @Override
    public void onHostPause() {
    }

    @Override
    public void onHostDestroy() {
        // ... do nothing
    }

}
