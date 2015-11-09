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

    // Do any additional setup after loading the view, typically from a nib.
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
    vibratePhone();
    
    
    return 1;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



// Yeah, global variables suck, but it's kind of a necessary evil here
AudioUnit *audioUnit = NULL;
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
    
    if(AudioSessionInitialize(NULL, NULL, NULL, NULL) != noErr) {
        return 1;
    }
    
    if(AudioSessionSetActive(true) != noErr) {
        return 1;
    }
    
    UInt32 sessionCategory = kAudioSessionCategory_RecordAudio;
    if(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                               sizeof(UInt32), &sessionCategory) != noErr) {
        return 1;
    }
    
    Float32 bufferSizeInSec = 0.02f;
    if(AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration,
                               sizeof(Float32), &bufferSizeInSec) != noErr) {
        return 1;
    }
    
    UInt32 overrideCategory = 1;
    if(AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker,
                               sizeof(UInt32), &overrideCategory) != noErr) {
        return 1;
    }
    
    // There are many properties you might want to provide callback functions for:
    // kAudioSessionProperty_AudioRouteChange
    // kAudioSessionProperty_OverrideCategoryEnableBluetoothInput
    // etc.
    
    return 0;
}
int initAudioStreams(AudioUnit *audioUnit) {
    UInt32 audioCategory = kAudioSessionCategory_RecordAudio;
    if(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
                               sizeof(UInt32), &audioCategory) != noErr) {
        return 1;
    }
    
    UInt32 overrideCategory = 1;
    if(AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker,
                               sizeof(UInt32), &overrideCategory) != noErr) {
        // Less serious error, but you may want to handle it and bail here
    }
    
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
    // You might want to replace this with a different value, but keep in mind that the
    // iPhone does not support all sample rates. 8kHz, 22kHz, and 44.1kHz should all work.
    streamDescription.mSampleRate = 44100;
    // Yes, I know you probably want floating point samples, but the iPhone isn't going
    // to give you floating point data. You'll need to make the conversion by hand from
    // linear PCM <-> float.
    streamDescription.mFormatID = kAudioFormatLinearPCM;
    // This part is important!
    streamDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger |
    kAudioFormatFlagsNativeEndian |
    kAudioFormatFlagIsPacked;
    // Not sure if the iPhone supports recording >16-bit audio, but I doubt it.
    streamDescription.mBitsPerChannel = 16;
    // 1 sample per frame, will always be 2 as long as 16-bit samples are being used
    streamDescription.mBytesPerFrame = 2;
    // Record in mono. Use 2 for stereo, though I don't think the iPhone does true stereo recording
    streamDescription.mChannelsPerFrame = 1;
    streamDescription.mBytesPerPacket = streamDescription.mBytesPerFrame *
    streamDescription.mChannelsPerFrame;
    // Always should be set to 1
    streamDescription.mFramesPerPacket = 1;
    // Always set to 0, just to be sure
    streamDescription.mReserved = 0;
    
    // Set up input stream with above properties
    if(AudioUnitSetProperty(*audioUnit, kAudioUnitProperty_StreamFormat,
                            kAudioUnitScope_Input, 0, &streamDescription, sizeof(streamDescription)) != noErr) {
        return 1;
    }
    
    // Ditto for the output stream, which we will be sending the processed audio to
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
        // Lazy initialization of this buffer is necessary because we don't
        // know the frame count until the first callback
        convertedSampleBuffer = (float*)malloc(sizeof(float) * numFrames);
    }
    if (inData==NULL){
        inData = (double*)malloc(sizeof(double)*numFrames);
    }
    if (peakIndexArray==NULL) {
        peakIndexArray = (int *)malloc(sizeof(int) * 700);
        
    }
    
    SInt16 *inputFrames = (SInt16*)(buffers->mBuffers->mData);
    
    // If your DSP code can use integers, then don't bother converting to
    // floats here, as it just wastes CPU. However, most DSP algorithms rely
    // on floating point, and this is especially true if you are porting a
    // VST/AU to iOS.
    for(int i = 0; i < numFrames; i++) {
        convertedSampleBuffer[i] = (float)inputFrames[i] / 32768;
        //   NSLog(@"Sample is: %f",convertedSampleBuffer[i]);
    }
    
    // Now we have floating point sample data from the render callback! We
    // can send it along for further processing, for example:
    // plugin->processReplacing(convertedSampleBuffer, NULL, sampleFrames);
    
    // Assuming that you have processed in place, we can now write the
    // floating point data back to the input buffer.
    for(int i = 0; i < numFrames; i++) {
        // Note that we multiply by 32767 here, NOT 32768. This is to avoid
        // overflow errors (and thus clipping).
        inputFrames[i] = (SInt16)(convertedSampleBuffer[i] * 32767/4); //double or SInt16
        inData[i] = (double)(convertedSampleBuffer[i] * 32767);
        // NSLog(@"inputFrames is: %d",inputFrames[i]);
        //        if (inData[i] > 4000) {
        //            printf("Detected  ");
        //            NSLog(@"inputFrames is: %d",inputFrames[i]);
        //            NSLog(@"inData is: %f",inData[i]);
        //        }
        
    }
    
    //    // 1. First initialize the class
    OouraFFT *fftBuffer = [[OouraFFT alloc] initForSignalsOfLength:1024 andNumWindows:10];
    //
    //    // 2. Then fill up an array with data with your own function
    fftBuffer.inputData = inData;
    //
    //
    //    // 3. And then compute the FFT
    [fftBuffer calculateWelchPeriodogramWithNewSignalSegment];
    //   printf("FFT done  ");
    
    
    // 4. ... then finally, plot the signal with your own function
    //doSomethingWithTheFrequencyData(fftBuffer.spectrumData)
    //    for(int i =0; i < 512;i++){
    //        //  NSLog(@"FFTDATA is: %f",fftBuffer.spectrumData[i]);
    //        NSString *myString = [NSString stringWithFormat:@"%f", fftBuffer.spectrumData[i]];
    //        printf("%s", [myString UTF8String]);
    //        printf("\n");
    //        if (i == 511){
    //            printf("===========DONE==================\n");
    //        }
    //
    //    }
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
    
    if (peakValue>3*sndPValue) {
        NSString *peakIndexString = [NSString stringWithFormat:@"%d", peakIndex];
        peakIndexArray[indexCnt]=peakIndex;
        if (indexCnt==19 && sirenFound > 19) {
            if (peakIndexArray[indexCnt]<peakIndexArray[indexCnt-19]-5 ||peakIndexArray[indexCnt]>peakIndexArray[indexCnt-19]+5) {
                NSString *otherIndexCntString = [NSString stringWithFormat:@"%d", indexCnt];
                printf("\n");
                printf("other IndexCnt %s",[otherIndexCntString UTF8String]);
                printf("\n");
                NSLog(@"Current Index is: %d",peakIndexArray[indexCnt]);
                printf("\n");
                NSLog(@"Other Index is: %d",peakIndexArray[indexCnt-19]);


                
                bimodal++;
                
            }
        }
        printf("%s", [peakIndexString   UTF8String]);
        printf("\n");
        sirenFound++;
        frameCnt++;
        
    }
    else{
        peakIndexArray[indexCnt]=peakIndex;
        frameCnt++;
        indexCnt++;
        printf("-");
        if (sirenFound<3) {
            bimodal=0;
        }
    }
    if (indexCnt==20) {
        indexCnt=0;
    }
    
    if (frameCnt==300) {
        printf("======end=====\n");
        NSString *sirenFoundString = [NSString stringWithFormat:@"%d", sirenFound];
        
        printf("SirenCount:%s", [sirenFoundString UTF8String]);
        printf("\n");
        if (bimodal>2) {
            printf("Bimodal\n");
        }else{
            printf("Not bimodal\n");
        }
        if (sirenFound>80 && bimodal>1) {
            
            
            sirenDetected =true;
            dispatch_async(dispatch_get_main_queue(), ^{
                stopProcessingAudio(audioUnit);
            });
            printf("sirenDetected\n");
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

- (void)dealloc {
    //i am not sure if all of these steps are neccessary. or if you just call DisposeAUGraph
    free(inData);
    free(convertedSampleBuffer);
    
    
}


@end