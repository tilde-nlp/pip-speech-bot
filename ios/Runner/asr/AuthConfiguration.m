
#import "AuthConfiguration.h"
#import <CommonCrypto/CommonDigest.h>

@implementation AuthConfiguration

@synthesize basicAuthUsername = _basicAuthUsername;
@synthesize basicAuthPassword = _basicAuthPassword;

- (id) init
{
    self = [super init];
    _token = nil;
    return self;
}

- (void)invalidateToken
{
    _token = nil;
}

- (void)requestToken:(void (^)(AuthConfiguration *))completionHandler
{
    if (self.tokenGenerator) {
        if (!_token) {
            self.tokenGenerator(^(NSString *token) {
                self->_token = token;
                completionHandler(self);
            });
        } else {
            completionHandler(self);
        }
    } else {
        completionHandler(self);
    }
}

- (NSMutableDictionary*) _createRequestHeaders {
    NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
    if (self.tokenGenerator) {
        if (self.token) {
            [headers setObject:self.token forKey:@"X-Authorization-Token"];
        }
    } else if(self.basicAuthPassword && self.basicAuthUsername) {
        NSString *authStr = [NSString stringWithFormat:@"%@:%@", self.basicAuthUsername,self.basicAuthPassword];
        NSData *authData = [authStr dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64;
        if ([authData respondsToSelector:@selector(base64EncodedStringWithOptions:)]) {
            base64 = [authData base64EncodedStringWithOptions:0];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            base64 = [authData base64Encoding];
#pragma clang diagnostic pop
        }
        NSString *authValue = [NSString stringWithFormat:@"Basic %@", base64];
        [headers setObject:authValue forKey:@"Authorization"];
    }
    
    return headers;
}

- (NSDictionary*) createRequestHeaders {
    return [self _createRequestHeaders];
}

- (NSString *) calculateSHA: (NSString *)text {
    const char *ptr = [text UTF8String];
    
    int i = 0;
    int len = (int)strlen(ptr);
    Byte byteArray[len];
    while (i != len) {
        unsigned eachChar = *(ptr + i);
        unsigned low8Bits = eachChar & 0xFF;
        
        byteArray[i] = low8Bits;
        i++;
    }
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1(byteArray, len, digest);
    
    NSMutableString *hex = [NSMutableString string];
    for (int i=0; i<20; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    NSString *immutableHex = [NSString stringWithString:hex];
    
    return immutableHex;
}

@end
