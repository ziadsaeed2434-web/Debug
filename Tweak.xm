#import <Foundation/Foundation.h>
#import "DebugOverlay.h"
#import <objc/runtime.h>

// Hook NSURLSession to monitor Ad network and Mediation HTTP traffic
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler {
    NSURL *url = request.URL;
    NSString *host = url.host;
    
    if ([host containsString:@"unity3d.com"] || [host containsString:@"vungle.com"] || [host containsString:@"inmobi.com"] || [host containsString:@"amplitude.com"]) {
        
        void (^wrappedHandler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
            NSInteger status = httpResp.statusCode;
            
            NSString *sdkName = @"Unknown";
            if ([host containsString:@"vungle"]) sdkName = @"Vungle";
            else if ([host containsString:@"inmobi"]) sdkName = @"InMobi";
            else if ([host containsString:@"unity3d"] || [host containsString:@"mediation"]) sdkName = @"LevelPlay/Unity";
            
            NSString *reqType = @"API";
            if ([url.path containsString:@"auction"]) reqType = @"AUCTION";
            else if ([url.path containsString:@"init"]) reqType = @"INIT";
            else if ([url.path containsString:@"reward"] || [url.path containsString:@"sdk"]) reqType = @"REWARD_LOG";
            
            [[DebugOverlay sharedInstance] logNetwork:host method:request.HTTPMethod status:status sdk:sdkName type:reqType];
            
            if (error) {
                [[DebugOverlay sharedInstance] logEvent:@"ERROR" message:[NSString stringWithFormat:@"Network Error on %@: %@", host, error.localizedDescription]];
            } else if (status == 200 && data) {
                // فحص استجابات No-Fill في الـ JSON بحذر
                NSString *respString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (respString && ([respString containsString:@"no_fill"] || [respString containsString:@"NO_FILL"])) {
                    [[DebugOverlay sharedInstance] logEvent:@"NO_FILL" message:[NSString stringWithFormat:@"Received NO_FILL from %@", host]];
                }
            }
            
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        };
        
        return %orig(request, wrappedHandler);
    }
    
    return %orig;
}

%end

// Hook LevelPlay / IronSource Initialization & Rewarded Delegates if present in Runtime
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[DebugOverlay sharedInstance] showOverlay];
        [[DebugOverlay sharedInstance] logEvent:@"INIT" message:@"RewardedDebugTweak injected successfully. Inspecting runtime classes..."];
        
        // تفقد وجود كلاسات LevelPlay أو IronSource في الـ Runtime واكتشاف الإصدار
        Class isAgent = objc_getClass("IronSource");
        if (isAgent) {
            [[DebugOverlay sharedInstance] logEvent:@"MEDIATION" message:@"IronSource / LevelPlay Class Found in Runtime!"];
        } else {
            [[DebugOverlay sharedInstance] logEvent:@"MEDIATION" message:@"IronSource Class NOT directly found, inspecting wrappers..."];
        }
        
        // فحص NSUserDefaults للإعدادات والـ Capping
        NSUserDefaults *def = [NSUserDefaults standardUserDefaults];
        NSString *userId = [def stringForKey:@"com.supersonic.mediation.USER_ID_KEY"];
        NSString *attVal = [def stringForKey:@"attValue"];
        BOOL capEnabled = [def boolForKey:@"RV_CappingManager.IS_CAP_ENABLED_DefaultRewardedVideo"];
        
        [[DebugOverlay sharedInstance] logEvent:@"CONFIG" message:[NSString stringWithFormat:@"User ID: %@ | ATT: %@ | RV Capped: %@", userId ?: @"None", attVal ?: @"N/A", capEnabled ? @"YES" : @"NO"]];
    });
}
