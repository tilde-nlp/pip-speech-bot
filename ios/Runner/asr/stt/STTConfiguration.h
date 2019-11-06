#import <Foundation/Foundation.h>
#import "../AuthConfiguration.h"

// URLS
#define  DEFAULT_STT_API_ENDPOINT @"https://runa.tilde.lv/client/ws/speech/LVASR-ONLINE"
//E.K.
#define  AUDIO_FRAME_SIZE 160
#define  AUDIO_SAMPLE_RATE 16000.0
#define  AUDIO_CODEC_TYPE_PCM @"audio/x-raw,+rate=(int)16000,+format=(string)S16LE"
#define  AUDIO_CODEC @"?content-type=%@,+layout=(string)interleaved,+channels=(int)1"

// timeout
#define  INACTIVITY_TIMEOUT 30

// models

@interface STTConfiguration : AuthConfiguration

@property NSString *Codec;
@property NSString *audioCodec;
@property NSNumber *interimResults;
@property NSNumber *continuous;
@property NSNumber *inactivityTimeout;
@property NSNumber *keywordsThreshold;
@property NSNumber *maxAlternatives;
@property NSNumber *wordAlternativesThreshold;
@property BOOL timestamps;

@property NSURL *apiEndpoint;
@property BOOL isCertificateValidationDisabled;

// Tilde v0 authorization
@property NSString *appID;
@property NSString *appSecret;
@property NSString *groupId;

- (id)init;

- (NSURL*)getWebSocketRecognizeURL;

- (NSString *)getStartMessage;

@end
