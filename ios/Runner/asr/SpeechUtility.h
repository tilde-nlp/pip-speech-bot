#import <Foundation/Foundation.h>
#import "AuthConfiguration.h"

#define WEBSOCKETS_ERROR_CODE 506

#define HTTP_METHOD_GET @"GET"
#define HTTP_METHOD_POST @"POST"
#define HTTP_METHOD_PUT @"PUT"
#define HTTP_METHOD_DELETE @"DELETE"

@interface SpeechUtility : NSObject
+ (NSError *)raiseErrorWithCode:(NSInteger)code;
+ (NSString*)findUnexpectedErrorWithCode: (NSInteger)code;
+ (NSError*)raiseErrorWithCode: (NSInteger)code message: (NSString*) errorMessage reason: (NSString*) reasonMessage suggestion:(NSString*) suggestionMessage;
+ (NSError*)raiseErrorWithMessage:(NSString*) errorMessage;

+ (void) processJSON: (void (^)(id, NSError*))handler
                  config: (AuthConfiguration*) authConfig
                response: (NSURLResponse*) httpResponse
                    data: (NSData*) responseData
                   error: (NSError*) requestError;
+ (void) processData: (void (^)(id, NSError*))handler
              config: (AuthConfiguration*) authConfig
            response: (NSURLResponse*) httpResponse
                data: (NSData*) responseData
               error: (NSError*) requestError;
@end
