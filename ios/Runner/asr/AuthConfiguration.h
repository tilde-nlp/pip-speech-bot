#import <Foundation/Foundation.h>

@interface AuthConfiguration : NSObject

@property NSString* basicAuthUsername;
@property NSString* basicAuthPassword;

@property (readonly) NSString *token;
@property (copy, nonatomic) void (^tokenGenerator) (void (^tokenHandler)(NSString *token));

- (void) invalidateToken;
- (void) requestToken: (void(^)(AuthConfiguration *config)) completionHandler;
- (NSString *)calculateSHA: (NSString *)text;

@end
