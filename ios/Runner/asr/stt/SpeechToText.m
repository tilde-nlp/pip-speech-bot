#import "SpeechToText.h"
#import "AuthConfigurationInternal.h"

// type defs for block callbacks
#define NUM_BUFFERS 3
typedef void (^RecognizeCallbackBlockType)(NSDictionary*, NSError*);
typedef void (^PowerLevelCallbackBlockType)(float);
typedef void (^AudioDataCallbackBlockType)(NSData*);

typedef struct
{
    AudioStreamBasicDescription  dataFormat;
    AudioQueueRef                queue;
    AudioQueueBufferRef          buffers[NUM_BUFFERS];
    AudioFileID                  audioFile;
    SInt64                       currentPacket;
    bool                         recording;
    int                          slot;
} RecordingState;


@interface SpeechToText()

@property NSString* pathPCM;
@property NSTimer *PeakPowerTimer;
@property RecordingState recordState;
@property WebSocketAudioStreamer *audioStreamer;
@property (nonatomic, copy) RecognizeCallbackBlockType recognizeCallback;
@property (nonatomic, copy) PowerLevelCallbackBlockType powerLevelCallback;

// For capturing data has been sent out
@property (nonatomic, copy) AudioDataCallbackBlockType audioDataCallback;

@end

@implementation SpeechToText

@synthesize recognizeCallback;
@synthesize powerLevelCallback;
@synthesize audioDataCallback;


// static for use by c code
static BOOL isNewRecordingAllowed;
//static BOOL isCompressedOpus;
static int audioRecordedLength;

id audioStreamerRef;

#pragma mark public methods

/**
 *  Static method to return a SpeechToText object given the service url
 *
 *  @param newURL the service url for the STT service
 *
 *  @return SpeechToText
 */
+(id)initWithConfig:(STTConfiguration *)config {
    SpeechToText *stt = [[self alloc] initWithConfig:config] ;
    return stt;
}

/**
 *  init method to return a SpeechToText object given the service url
 *
 *  @param newURL the service url for the STT service
 *
 *  @return SpeechToText
 */
- (id)initWithConfig:(STTConfiguration *)config {
    self = [super init];
    self.config = config;
    isNewRecordingAllowed = YES;

    return self;
}

/**
 *  stream audio from the device microphone to the STT service
 *
 *  @param recognizeHandler (^)(NSDictionary*, NSError*)
 */
- (void) recognize:(void (^)(NSDictionary*, NSError*)) recognizeHandler {
    [self recognize:recognizeHandler dataHandler:nil powerHandler:nil];
}

/**
 *  stream audio from the device microphone to the STT service
 *
 *  @param recognizeHandler (^)(NSDictionary*, NSError*)
 *  @param powerHandler (void (^)(float))
 */
- (void) recognize: (void (^)(NSDictionary*, NSError*)) recognizeHandler
       dataHandler: (void (^)(NSData *)) dataHandler {
    [self recognize:recognizeHandler dataHandler:dataHandler powerHandler:nil];
}

/**
 *  stream audio from the device microphone to the STT service
 *
 *  @param recognizeHandler (^)(NSDictionary*, NSError*)
 *  @param powerHandler (void (^)(float))
 */
- (void) recognize: (void (^)(NSDictionary*, NSError*)) recognizeHandler
      powerHandler: (void (^)(float)) powerHandler {
    [self recognize:recognizeHandler dataHandler:nil powerHandler:powerHandler];
}

/**
 *  stream audio from the device microphone to the STT service
 *
 *  @param recognizeHandler (^)(NSDictionary*, NSError*)
 *  @param dataHandler (void (^) (NSData*))
 *  @param powerHandler (void (^)(float))
 */
- (void) recognize: (void (^)(NSDictionary*, NSError*)) recognizeHandler
       dataHandler: (void (^)(NSData*)) dataHandler
      powerHandler: (void (^)(float)) powerHandler {
    self.recognizeCallback = recognizeHandler;
    self.audioDataCallback = dataHandler;
    self.powerLevelCallback = powerHandler;

    if (!isNewRecordingAllowed) {
        // don't allow a new recording to be allowed until this transaction has completed
        // NSError *recordError = [SpeechUtility raiseErrorWithMessage:@"A voice query is already in progress"];
        // self.recognizeCallback(nil, recordError);
        return;
    }
    isNewRecordingAllowed = NO;

    if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)]) {
        // iOS 7.x and above. Needs to ask permission
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            // Make sure to startRecordingAudio on a thread that has a run loop otherwise audio will not work
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (granted) {
                    // Permission granted
                    [self startRecordingAudio];
                } else {
                    // Permission denied
                    isNewRecordingAllowed = YES;
                    NSError *recordError = [SpeechUtility raiseErrorWithMessage:@"Record permission denied"];
                    self.recognizeCallback(nil, recordError);
                }
            }];
        }];
    } else {
        // iOS 6.x: Permission is always granted.
        [self startRecordingAudio];
    }
}

/**
 *  send out end marker of a stream
 *
 *  @return YES if the data has been sent directly; NO if the data is bufferred because the connection is not established
 */
-(BOOL) endTransmission {
    return [[self audioStreamer] sendEndOfStreamMarker];
}

/**
 *  Disconnect
 */
-(void) endConnection {
    [[self audioStreamer] disconnect:@"Manually terminating socket connection"];
}

/**
 *  stopRecording and streaming audio from the device microphone
 *
 *  @return void
 */
-(void) endRecognize {
    [self stopRecordingAudio];
    [self endTransmission];
    // kill the handler references?
    self.recognizeCallback = nil;
    self.audioDataCallback = nil;
    self.powerLevelCallback = nil;
    // kill the streamer references? - this seems to solve some retain cycle problems...
    [self endConnection];
    self.audioStreamer = nil;
}

/**
 *  getTranscript - convenience method to get the transcript from the JSON results
 *
 *  @param results NSDictionary containing parsed JSON returned from the service
 *
 *  @return NSString containing transcript
 */
-(NSString*) getTranscript:(NSDictionary*) results {
    
    if ([results objectForKey:@"result"] != nil) {
        
        NSDictionary *resultArray = [results objectForKey:@"result"];
        if ([resultArray objectForKey:@"hypotheses"] !=  nil) {
            NSArray *alternatives = [resultArray objectForKey:@"hypotheses"];
            if ([alternatives objectAtIndex:0] != nil) {
                NSDictionary *alternative = [alternatives objectAtIndex:0];
                if ([alternative objectForKey:@"transcript"] != nil) {
                    NSString *transcript = [alternative objectForKey:@"transcript"];
                    return transcript;
                }
            }
        }
    }
    return nil;
}

/**
 *  getConfidenceScore - convenience method to get the confidence score from the JSON results
 *
 *  @param results NSDictionary containing parsed JSON returned from the service
 *
 *  @return NSNumber containing score
 */
-(NSNumber*) getConfidenceScore:(NSDictionary*) results {
    if ([results objectForKey:@"results"] != nil) {
        NSArray *resultArray = [results objectForKey:@"results"];
        
        if ([resultArray count] != 0 && [resultArray objectAtIndex:0] != nil) {
            NSDictionary *result = [resultArray objectAtIndex:0];
            NSArray *alternatives = [result objectForKey:@"alternatives"];
            
            if ([alternatives objectAtIndex:0] != nil) {
                NSDictionary *alternative = [alternatives objectAtIndex:0];
            
                if ([alternative objectForKey:@"confidence"] != nil) {
                    NSNumber *confidence = [alternative objectForKey:@"confidence"];
                    return confidence;
                }
            }
        }
    }
    
    return nil;
}

/**
 *  isFinalTranscript : check the 'final' value in the dictionary and return
 *
 *  @param results NSDictionary
 *
 *  @return BOOL
 */
-(BOOL) isFinalTranscript:(NSDictionary*) results {
    if ([results objectForKey:@"result"] != nil) {
        NSDictionary *finalResults = [results objectForKey:@"result"];
        if ([finalResults  objectForKey:@"final"] !=  nil) {
            return [[finalResults objectForKey:@"final"] boolValue];
        }
    }
    
    return NO;
}

/**
 *  getPowerLevel - listen for updates to the Db level of the speaker, can be used for a voice wave visualization
 *
 *  @param powerHandler - callback block
 */
- (void) getPowerLevel:(void (^)(float)) powerHandler {
    self.powerLevelCallback = powerHandler;
}

#pragma mark private methods

/**
 *  Start recording audio
 */
- (void) startRecordingAudio {
    // lets start the socket connection right away
    [self initializeStreaming];
    [self setupAudioFormat:&_recordState.dataFormat];
    
    _recordState.currentPacket = 0;
    audioRecordedLength = 0;
    
    OSStatus status = AudioQueueNewInput(&_recordState.dataFormat,
                                         AudioInputStreamingCallback,
                                         &_recordState,
                                         CFRunLoopGetCurrent(),
                                         kCFRunLoopCommonModes,
                                         0,
                                         &_recordState.queue);
    
    
    if (status == 0) {
        
        for(int i = 0; i < NUM_BUFFERS; i++) {
            AudioQueueAllocateBuffer(_recordState.queue,  AUDIO_SAMPLE_RATE, &_recordState.buffers[i]);
//            AudioQueueAllocateBuffer(_recordState.queue, 4096, &_recordState.buffers[i]);
            AudioQueueEnqueueBuffer(_recordState.queue, _recordState.buffers[i], 0, NULL);
        }

        _recordState.recording = true;
        status = AudioQueueStart(_recordState.queue, NULL);
        if (status == 0) {

            UInt32 enableMetering = 1;
            status = AudioQueueSetProperty(_recordState.queue, kAudioQueueProperty_EnableLevelMetering, &enableMetering, sizeof(enableMetering));

            // start peak power timer
            if (status == 0) {
                self.PeakPowerTimer = [NSTimer scheduledTimerWithTimeInterval:0.125
                                                                       target:self
                                                                     selector:@selector(samplePeakPower)
                                                                     userInfo:nil
                                                                      repeats:YES];
            }
        } else {
            NSLog(@"AudioQueueStart failed with OSStatus: %d", (int)status);
        }
    }
}

/**
 *  Stop recording
 */
- (void) stopRecordingAudio {
    if (isNewRecordingAllowed) {
        NSLog(@"### Record stopped ###");
        return;
    }
    NSLog(@"### Stopping recording ###");
    if (self.PeakPowerTimer) {
        [self.PeakPowerTimer invalidate];
    }
    
    self.PeakPowerTimer = nil;

    if (_recordState.queue != NULL){
        AudioQueueReset(_recordState.queue);
    }
    if (_recordState.queue != NULL){
        AudioQueueStop(_recordState.queue, YES);
    }
    if (_recordState.queue != NULL){
        AudioQueueDispose(_recordState.queue, YES);
    }
    isNewRecordingAllowed = YES;
}


/**
 *  samplePeakPower - Get the decibel level from the AudioQueue
 */
- (void) samplePeakPower {
    AudioQueueLevelMeterState meters[1];
    UInt32 dlen = sizeof(meters);
    OSErr Status = AudioQueueGetProperty(_recordState.queue,kAudioQueueProperty_CurrentLevelMeterDB,meters,&dlen);

    if (Status == 0) {
        if (self.powerLevelCallback != nil) {
            self.powerLevelCallback(meters[0].mAveragePower);
        }
    }
}



#pragma mark audio streaming

/**
 *  Initialize streaming
 */
- (void) initializeStreaming {

    // init the websocket streamer
    self.audioStreamer = [[WebSocketAudioStreamer alloc] init];
    [self.audioStreamer setRecognizeHandler:recognizeCallback];
    [self.audioStreamer setAudioDataHandler:audioDataCallback];

    // connect if we are not connected
    if (![self.audioStreamer isWebSocketConnected]) {
        [self.config requestToken:^(AuthConfiguration *config) {
            [self.audioStreamer connect:(STTConfiguration*)config
                                headers:[config createRequestHeaders]];
        }];
    }
    
    // set a pointer to the wsuploader class so it is accessible in the c callback
    audioStreamerRef = self.audioStreamer;
}

#pragma mark audio

- (void)setupAudioFormat:(AudioStreamBasicDescription*)format {
    format->mSampleRate =  AUDIO_SAMPLE_RATE;
    format->mFormatID = kAudioFormatLinearPCM;
    format->mFramesPerPacket = 1;
    format->mChannelsPerFrame = 1;
    format->mBytesPerFrame = 2;
    format->mBytesPerPacket = 2;
    format->mBitsPerChannel = 16;
    format->mReserved = 0;
    format->mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian ;
    //kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
}

int getAudioRecordedLengthInMs() {
    return audioRecordedLength/32;
}

#pragma mark audio callbacks

void AudioInputStreamingCallback(
                                 void *inUserData,
                                 AudioQueueRef inAQ,
                                 AudioQueueBufferRef inBuffer,
                                 const AudioTimeStamp *inStartTime,
                                 UInt32 inNumberPacketDescriptions,
                                 const AudioStreamPacketDescription *inPacketDescs) {
    OSStatus status = 0;
    RecordingState* recordState = (RecordingState*)inUserData;
    
    NSData *data = [NSData dataWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
    audioRecordedLength += [data length];

    [audioStreamerRef writeData:data];

    if(status == 0) {
        recordState->currentPacket += inNumberPacketDescriptions;
    }
    AudioQueueEnqueueBuffer(recordState->queue, inBuffer, 0, NULL);
}

@end

