//
//  ViewController.m
//  webStream
//
//  Created by Kyle Griffith on 2015-10-16.
//  Copyright (c) 2015 Kyle Griffith. All rights reserved.
//

#import "ViewController.h"
#import "SirenViewController.h"
#import "FFT.h"
@import AudioUnit;
@import AudioToolbox;
@import UIKit;
@interface ViewController()
@property(readonly) NSArray * availableInputs NS_AVAILABLE_IOS(7_0);
@end

@implementation ViewController



- (void)viewDidLoad {
    [super viewDidLoad];
    
    initAudioSession();
    initAudioStreams(audioUnit);
    initAgain= false;
    
}
int vibratePhone() {
    AudioServicesPlaySystemSound (kSystemSoundID_Vibrate);
    return 1;
}
int SirenFunction() {
    
    UIAlertView *SirenAlert = [[UIAlertView alloc] initWithTitle:@"Siren Detected" message:@"There has been a siren detected in your area" delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil, nil];
    [SirenAlert show];
    
    
    return 1;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



// Yeah, global variables suck, but it's kind of a necessary evil here
AudioUnit *audioUnit = NULL;
int k=0;
float *convertedSampleBuffer = NULL;
double *inData = NULL;
int frameCnt = 0;
int sirenFound = 0;
bool sirenDetected = false;
double averageIndex = 0;
bool initAgain = false;
int *peakIndexArray = NULL;
int indexCnt=1;
int bimodal=0;
int initAudioSession() {
    audioUnit = (AudioUnit*)malloc(sizeof(AudioUnit));
    
    return 0;
}
int initAudioStreams(AudioUnit *audioUnit) {
    AudioComponentDescription componentDescription;
    componentDescription.componentType = kAudioUnitType_Output;
    componentDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    componentDescription.componentFlags = 0;
    componentDescription.componentFlagsMask = 0;
    AudioComponent component = AudioComponentFindNext(NULL, &componentDescription);
    if(AudioComponentInstanceNew(component, audioUnit) != noErr) {
        return 1;
    }
    
    UInt32 enable = 1;
    if(AudioUnitSetProperty(*audioUnit, kAudioOutputUnitProperty_EnableIO,
                            kAudioUnitScope_Input, 1, &enable, sizeof(UInt32)) != noErr) {
        return 1;
    }
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = renderCallback; // Render function
    callbackStruct.inputProcRefCon = NULL;
    if(AudioUnitSetProperty(*audioUnit, kAudioUnitProperty_SetRenderCallback,
                            kAudioUnitScope_Input, 0, &callbackStruct,
                            sizeof(AURenderCallbackStruct)) != noErr) {
        return 1;
    }
    
    AudioStreamBasicDescription streamDescription;
    streamDescription.mSampleRate = 44100;
    streamDescription.mFormatID = kAudioFormatLinearPCM;
    streamDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger |
    kAudioFormatFlagsNativeEndian |
    kAudioFormatFlagIsPacked;
    streamDescription.mBitsPerChannel = 16;
    streamDescription.mBytesPerFrame = 2;
    streamDescription.mChannelsPerFrame = 1;
    streamDescription.mBytesPerPacket = streamDescription.mBytesPerFrame *
    streamDescription.mChannelsPerFrame;
    streamDescription.mFramesPerPacket = 1;
    streamDescription.mReserved = 0;
    
    if(AudioUnitSetProperty(*audioUnit, kAudioUnitProperty_StreamFormat,
                            kAudioUnitScope_Input, 0, &streamDescription, sizeof(streamDescription)) != noErr) {
        return 1;
    }
    
    if(AudioUnitSetProperty(*audioUnit, kAudioUnitProperty_StreamFormat,
                            kAudioUnitScope_Output, 1, &streamDescription, sizeof(streamDescription)) != noErr) {
        return 1;
    }
    
    return 0;
}

- (IBAction)mySwitch:(id)sender {
    
    if ([sender isOn]) {
        if (initAgain) {
            initAudioSession();
            initAudioStreams(audioUnit);
        }
        startAudioUnit(audioUnit);
    }else {
        stopProcessingAudio(audioUnit);
        initAgain = true;
    }
}




int startAudioUnit(AudioUnit *audioUnit) {
    if(AudioUnitInitialize(*audioUnit) != noErr) {
        return 1;
    }
    
    if(AudioOutputUnitStart(*audioUnit) != noErr) {
        return 1;
    }
    
    return 0;
}


OSStatus renderCallback(void *userData, AudioUnitRenderActionFlags *actionFlags,
                        const AudioTimeStamp *audioTimeStamp, UInt32 busNumber,
                        UInt32 numFrames, AudioBufferList *buffers) {
    OSStatus status = AudioUnitRender(*audioUnit, actionFlags, audioTimeStamp,
                                      1, numFrames, buffers);
    
    
    numFrames = 1024;
    if(status != noErr) {
        return status;
    }
    
    if(convertedSampleBuffer == NULL) {
        convertedSampleBuffer = (float*)malloc(sizeof(float) * numFrames);
    }
    if (inData==NULL){
        inData = (double*)malloc(sizeof(double)*numFrames);
    }
    if (peakIndexArray==NULL) {
        peakIndexArray = (int *)malloc(sizeof(int) * 700);
        
    }
    SInt16 *inputFrames = (SInt16*)(buffers->mBuffers->mData);
    
    for(int i = 0; i < numFrames; i++) {
        convertedSampleBuffer[i] = (float)inputFrames[i] / 32768;
    }
    for(int i = 0; i < numFrames; i++) {
        inputFrames[i] = (SInt16)(convertedSampleBuffer[i] * 32767); //double or SInt16
        inData[i] = (double)(convertedSampleBuffer[i] * 32767);
    }
    
    OouraFFT *fftBuffer = [[OouraFFT alloc] initForSignalsOfLength:1024 andNumWindows:10];
    fftBuffer.inputData = inData;
    [fftBuffer calculateWelchPeriodogramWithNewSignalSegment];

    int lowIndex= 4;
    int highIndex=64;
    int peakIndex =4;
    int filterIndex=4;
    
    double peakValue = fftBuffer.spectrumData[lowIndex];
    double sndPValue = fftBuffer.spectrumData[lowIndex];
    for (int i = lowIndex; i <highIndex; i++) {
        if (peakValue <fftBuffer.spectrumData[i]) {
            peakValue=fftBuffer.spectrumData[i];
            peakIndex= i;
        }
    }
    
    for (int j = lowIndex; j < highIndex; j++) {
        if (j<=peakIndex-filterIndex || j>=peakIndex+filterIndex) {
            if (sndPValue <fftBuffer.spectrumData[j]){
                sndPValue = fftBuffer.spectrumData[j];
            }
        }
        
    }
    int indexOffset = 19;
    int valueToCompare = 5;
    int testEnd=120;
    int sirenMinimum= 30;
    int isBimodal=2;
    if (peakValue>3*sndPValue) {
        NSString *peakIndexString = [NSString stringWithFormat:@"%d", peakIndex];
        peakIndexArray[indexCnt]=peakIndex;
        if (indexCnt==indexOffset && sirenFound > indexOffset) {
            if (peakIndexArray[indexCnt]<peakIndexArray[indexCnt-indexOffset]-valueToCompare ||peakIndexArray[indexCnt]>peakIndexArray[indexCnt-indexOffset]+valueToCompare) {

                bimodal++;
                
            }
        }
        printf("%s", [peakIndexString   UTF8String]);
        printf("\n");
        sirenFound++;
        frameCnt++;
        
    }
    else{
        int youngSignal=3;
        peakIndexArray[indexCnt]=peakIndex;
        frameCnt++;
        indexCnt++;
        printf("-");
        if (sirenFound<youngSignal) {
            bimodal=0;
        }
    }
    if (indexCnt==indexOffset) {
        indexCnt=0;
    }
    
    if (frameCnt==testEnd) {
        printf("\n======end=====\n");
        NSString *sirenFoundString = [NSString stringWithFormat:@"%d", sirenFound];
        
        printf("SirenCount:%s", [sirenFoundString UTF8String]);
        printf("\n");
        if (bimodal>isBimodal) {
            printf("Bimodal\n");
        }else{
            printf("Not bimodal\n");
        }
        if (sirenFound>sirenMinimum || bimodal>isBimodal) {
            //NOTE: bimodal is set to an option so its easier for you to set off the detection with a whistle
            
            sirenDetected =true;
            dispatch_async(dispatch_get_main_queue(), ^{
                stopProcessingAudio(audioUnit);
            });
            printf("Siren Detected\n");
        }else{
            sirenDetected=false;
        }
        frameCnt=0;
        sirenFound=0;
    }
    return noErr;
}


int stopProcessingAudio(AudioUnit *audioUnit) {
    if (sirenDetected) {
        sirenDetected= false;
        SirenFunction();
    }
    if(AudioOutputUnitStop(*audioUnit) != noErr) {
        return 1;
    }
    
    if(AudioUnitUninitialize(*audioUnit) != noErr) {
        return 1;
    }
    
    *audioUnit = NULL;
    return 0;
}



@end