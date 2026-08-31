#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <AdSupport/AdSupport.h>

// إحداثيات أتلانتا، جورجيا
#define ATLANTA_LAT_MIN 33.7489
#define ATLANTA_LAT_MAX 33.7900
#define ATLANTA_LNG_MIN -84.4200
#define ATLANTA_LNG_MAX -84.3800

static double currentLatitude = 33.7490;
static double currentLongitude = -84.3880;
static NSString *currentIDFA = nil;
static NSString *currentAtlantaResidentialIP = nil;
static NSArray *atlantaResidentialSubnets = nil;

static double randomInRange(double min, double max) {
    return min + (arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX) * (max - min);
}

static void rotateIDFA(void) {
    currentIDFA = [[NSUUID UUID] UUIDString];
}

static void generateAtlantaResidentialIP(void) {
    @autoreleasepool {
        if (!atlantaResidentialSubnets) {
            atlantaResidentialSubnets = @[
                @{@"prefix": @"73.140.", @"min": @0, @"max": @255},   
                @{@"prefix": @"67.160.", @"min": @0, @"max": @255},   
                @{@"prefix": @"104.128.", @"min": @0, @"max": @255}, 
                @{@"prefix": @"24.98.",   @"min": @0, @"max": @255},   
                @{@"prefix": @"50.130.",  @"min": @0, @"max": @255}    
            ];
        }
        
        NSDictionary *subnetInfo = atlantaResidentialSubnets[arc4random_uniform((uint32_t)[atlantaResidentialSubnets count]);
        NSString *prefix = subnetInfo[@"prefix"];
        
        int thirdOctet = arc4random_uniform(254) + 1;
        int fourthOctet = arc4random_uniform(254) + 1;
        
        currentAtlantaResidentialIP = [NSString stringWithFormat:@"%@%d.%d", prefix, thirdOctet, fourthOctet];
    }
}

// دالة إعادة الضبط الآمنة بالكامل
static void performFullSessionReset(void) {
    @autoreleasepool {
        generateAtlantaResidentialIP();
        rotateIDFA();
        
        currentLatitude = randomInRange(ATLANTA_LAT_MIN, ATLANTA_LAT_MAX);
        currentLongitude = randomInRange(ATLANTA_LNG_MIN, ATLANTA_LNG_MAX);
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleID && [bundleID isEqualToString:@"com.codebysms"]) {
            // 1. مسح الـ NSUserDefaults بأمان
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleID];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            // 2. مسح ملفات الكاش (Caches) بأمان تام
            NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
            if (cacheDir) {
                NSFileManager *fileManager = [NSFileManager defaultManager];
                NSArray *contents = [fileManager contentsOfDirectoryAtPath:cacheDir error:nil];
                for (NSString *file in contents) {
                    [fileManager removeItemAtPath:[cacheDir stringByAppendingPathComponent:file] error:nil];
                }
            }
            
            // 3. مسح الكوكيز
            NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
                [cookieStorage deleteCookie:cookie];
            }
        }
    }
}

// ==========================================
// Hooks الشبكة الآمنة
// ==========================================
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    if (currentAtlantaResidentialIP) {
        NSMutableURLRequest *mutableReq = [request mutableCopy];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"Client-IP"];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Real-IP"];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"True-Client-IP"];
        return %orig(mutableReq, completionHandler);
    }
    return %orig(request, completionHandler);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (currentAtlantaResidentialIP) {
        NSMutableURLRequest *mutableReq = [request mutableCopy];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"Client-IP"];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Real-IP"];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"True-Client-IP"];
        return %orig(mutableReq);
    }
    return %orig(request);
}

%end

// ==========================================
// Hooks الموقع الجغرافي
// ==========================================
%hook CLLocationManager

- (void)startUpdatingLocation {
    %orig;
    CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:currentLatitude longitude:currentLongitude];
    if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
    }
}

- (CLLocation *)location {
    return [[CLLocation alloc] initWithLatitude:currentLatitude longitude:currentLongitude];
}

%end

%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    CLLocationCoordinate2D coord;
    coord.latitude = currentLatitude;
    coord.longitude = currentLongitude;
    return coord;
}

%end

// ==========================================
// Hooks المعرفات
// ==========================================
%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    if (currentIDFA) {
        return [[NSUUID alloc] initWithUUIDString:currentIDFA];
    }
    return %orig;
}

%end

%hook UIDevice

- (NSString *)identifierForVendor {
    return [[NSUUID UUID] UUIDString];
}

%end

// ==========================================
// نقطة البداية الآمنة جداً
// ==========================================
%ctor {
    @autoreleasepool {
        // تأخير التنفيذ لحين استقرار التطبيق كلياً في الذاكرة لتجنب أي تعارض
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
            if (bundleIdentifier && [bundleIdentifier isEqualToString:@"com.codebysms"]) {
                performFullSessionReset();
                
                [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                                  object:nil
                                                                   queue:[NSOperationQueue mainQueue]
                                                              usingBlock:^(NSNotification *note) {
                    performFullSessionReset();
                }];
            }
        });
    }
}
