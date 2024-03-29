/**
 * Copyright IBM Corporation 2015
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

#import <Foundation/Foundation.h>
#import "../stt/STTConfiguration.h"
#import "../SpeechUtility.h"

@interface WebSocketAudioStreamer : NSObject

- (BOOL) isWebSocketConnected;
- (void) connect:(STTConfiguration*)config headers:(NSDictionary*)headers;
- (void) reconnect;
- (void) disconnect:(NSString*) reason;
- (void) writeData:(NSData*) data;
- (void) setRecognizeHandler:(void (^)(NSDictionary*, NSError*))handler;
- (void) setAudioDataHandler:(void (^)(NSData*))handler;
- (BOOL) sendEndOfStreamMarker;


@end

