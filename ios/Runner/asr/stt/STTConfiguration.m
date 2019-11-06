#import "STTConfiguration.h"

@implementation STTConfiguration


- (id)init {
    self = [super init];
    
    // set default values
    [self setApiEndpoint:[NSURL URLWithString: DEFAULT_STT_API_ENDPOINT]];
    [self setAudioCodec: AUDIO_CODEC_TYPE_PCM];
    [self setCodec:[NSString stringWithFormat:AUDIO_CODEC, self.audioCodec]];
    [self setContinuous:[NSNumber numberWithBool:NO]];
    [self setInactivityTimeout:[NSNumber numberWithInt: INACTIVITY_TIMEOUT]];

    return self;
}

/**
 *  WebSockets URL of Speech Recognition
 *
 *  @return NSURL
 */
- (NSURL*)getWebSocketRecognizeURL {
    NSMutableString *uriStr = [[NSMutableString alloc] init];

    [uriStr appendFormat:@"%@%@", self.apiEndpoint, self.Codec];

    NSURL * url = [NSURL URLWithString:uriStr];
    return url;
}

/**
 *  Organize JSON string for start message of WebSockets
 *
 *  @return JSON string
 */
- (NSString *)getStartMessage{
    NSString *jsonString = @"";

    NSMutableDictionary *inputParameters = [[NSMutableDictionary alloc] init];

    NSTimeInterval milisecondedDate = ([[NSDate date] timeIntervalSince1970] );
    
    NSString *timeStampObj = [NSString stringWithFormat:@"%@", [NSNumber numberWithLong:milisecondedDate]];
    NSString *textToCrypt = [NSString stringWithFormat:@"%@%@%@", timeStampObj, self.appID, self.appSecret];
    
    // figure out post-processors
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName: self.groupId];
    BOOL numberConversion = [defaults boolForKey:@"asr_number_conversion"];
    BOOL punctuationConversion = [defaults boolForKey:@"asr_punctuation_conversion"];
    // post-processors
    // addpunc performs command conversion for LV
    // for LT, though, we need "commands"
    NSArray *postProcessors = nil;
    if (numberConversion && punctuationConversion) {
        // PIP1 doesn't need command recognition
        // postProcessors = @[@"numbers", @"commands2"];
        postProcessors = @[@"numbers"];
    } else if (numberConversion) {
        postProcessors = @[@"numbers"];
    }
 
    [inputParameters setValue:self.appID forKey:@"appID"];
    [inputParameters setValue:[self calculateSHA:textToCrypt] forKey:@"appKey"];
    [inputParameters setValue:timeStampObj forKey:@"timestamp"];
    if (postProcessors != nil) {
        [inputParameters setValue:postProcessors forKey:@"enable-postprocess"];
    }

    NSError *error = nil;
    if([NSJSONSerialization isValidJSONObject:inputParameters]){
        NSData *data = [NSJSONSerialization dataWithJSONObject:inputParameters options:0 error:&error];
        if(error == nil)
            jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return jsonString;
}

@end
