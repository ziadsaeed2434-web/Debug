#import <UIKit/UIKit.h>

@interface DebugOverlay : NSObject
+ (instancetype)sharedInstance;
- (void)showOverlay;
- (void)hideOverlay;
- (void)logEvent:(NSString *)category message:(NSString *)message;
- (void)logNetwork:(NSString *)host method:(NSString *)method status:(NSInteger)status sdk:(NSString *)sdk type:(NSString *)type;
@end
