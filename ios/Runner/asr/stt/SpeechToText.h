#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioFile.h>
#import "STTConfiguration.h"
#import "../websocket/WebSocketAudioStreamer.h"

@interface SpeechToText : NSObject <NSURLSessionDelegate>

@property (nonatomic,retain) STTConfiguration *config;

+(id)initWithConfig:(STTConfiguration *)config;
-(id)initWithConfig:(STTConfiguration *)config;

/**
 *  stream audio from the device microphone to the STT service
 *
 *  @param recognizeHandler (^)(NSDictionary*, NSError*)
 *  @param dataHandler      (^) (NSData*)
 *  @param powerHandler     (^)(float)
 */
- (void) recognize:(void (^)(NSDictionary*, NSError*)) recognizeHandler dataHandler: (void (^) (NSData*)) dataHandler
      powerHandler: (void (^)(float)) powerHandler;
/**
 *  stream audio from the device microphone to the STT service
 *
 *  @param recognizeHandler (^)(NSDictionary*, NSError*)
 *  @param dataHandler      (^) (NSData*)
 */
- (void) recognize:(void (^)(NSDictionary*, NSError*)) recognizeHandler dataHandler: (void (^) (NSData*)) dataHandler;
/**
 *  stream audio from the device microphone to the STT service
 *
 *  @param recognizeHandler (^)(NSDictionary*, NSError*)
 *  @param powerHandler     (^)(float)
 */
- (void) recognize:(void (^)(NSDictionary*, NSError*)) recognizeHandler powerHandler: (void (^)(float)) powerHandler;
/**
 *  stream audio from the device microphone to the STT service
 *
 *  @param recognizeHandler (^)(NSDictionary*, NSError*)
 */
- (void) recognize:(void (^)(NSDictionary*, NSError*)) recognizeHandler;

/**
 *  stopRecording and streaming audio from the device microphone
 *
 *  @return void
 */
- (void) endRecognize;

/**
 *  send out end marker
 *
 *  @return if the data has been sent directly, return NO if the data is bufferred because the connection is not established
 */
- (BOOL) endTransmission;

/**
 *  Disconnect
 */
- (void) endConnection;

/**
 * Stop recording
 */
- (void) stopRecordingAudio;


/**
 *  getTranscript - convenience method to get the transcript from the JSON results
 *
 *  @param results NSDictionary containing parsed JSON returned from the service
 *
 *  @return NSString containing transcript
 */
-(NSString*) getTranscript:(NSDictionary*) results;


/**
 *  getConfidenceScore - convenience method to get the confidence score from the JSON results
 *
 *  @param results NSDictionary containing parsed JSON returned from the service
 *
 *  @return NSNumber containing score
 */
-(NSNumber*) getConfidenceScore:(NSDictionary*) results;


/**
 *  isFinalTranscript : convenience method to check the 'final' value in the dictionary and return
 *
 *  @param results NSDictionary
 *
 *  @return BOOL
 */
-(BOOL) isFinalTranscript:(NSDictionary*) results;

/**
 *  getPowerLevel - listen for updates to the Db level of the speaker, can be used for a voice wave visualization
 *
 *  @param powerHandler - callback block
 */
- (void) getPowerLevel:(void (^)(float)) powerHandler;

@end

