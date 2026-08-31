#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <AdSupport/AdSupport.h>
#import <WebKit/WebKit.h>

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

// دالة لاختيار وتوليد IP حقيقي وسكني من نطاقات أتلانتا الحقيقية
static void generateAtlantaResidentialIP(void) {
    if (!atlantaResidentialSubnets) {
        // [تصحيح] إضافة علامة @ قبل الأرقام داخل القواميس Objective-C Literals
        atlantaResidentialSubnets = @[
            @{@"prefix": @"73.140.", @"min": @0, @"max": @255},   
            @{@"prefix": @"67.160.", @"min": @0, @"max": @255},   
            @{@"prefix": @"104.128.", @"min": @0, @"max": @255}, 
            @{@"prefix": @"24.98.",   @"min": @0, @"max": @255},   
            @{@"prefix": @"50.130.",  @"min": @0, @"max": @255}    
        ];
    }
    
    // [تصحيح] إضافة الأقواس المفقودة لاستخراج العنصر من المصفوفة بشكل صحيح
    NSDictionary *subnetInfo = atlantaResidentialSubnets[arc4random_uniform((uint32_t)[atlantaResidentialSubnets count])];
    NSString *prefix = subnetInfo[@"prefix"];
    
    int thirdOctet = arc4random_uniform(254) + 1;
    int fourthOctet = arc4random_uniform(254) + 1;
    
    currentAtlantaResidentialIP = [NSString stringWithFormat:@"%@%d.%d", prefix, thirdOctet, fourthOctet];
}

// دالة إعادة الضبط الشامل للجلسة
static void performFullSessionReset(void) {
    @autoreleasepool {
        generateAtlantaResidentialIP();
        rotateIDFA();
        
        currentLatitude = randomInRange(ATLANTA_LAT_MIN, ATLANTA_LAT_MAX);
        currentLongitude = randomInRange(ATLANTA_LNG_MIN, ATLANTA_LNG_MAX);
        
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.codebysms"]) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleID];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            // [تصحيح] استخدام NSCachesDirectory بدلاً من CachesDirectory الخاطئة
            NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
            NSFileManager *fileManager = [NSFileManager defaultManager];
            for (NSString *file in [fileManager contentsOfDirectoryAtPath:cacheDir error:nil]) {
                [fileManager removeItemAtPath:[cacheDir stringByAppendingPathComponent:file] error:nil];
            }
            
            if (@available(iOS 9.0, *)) {
                NSSet *websiteDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
                [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes 
                                                          modifiedSince:[NSDate distantPast] 
                                                      completionHandler:^{}];
            }
            
            NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
                [cookieStorage deleteCookie:cookie];
            }
        }
    }
}

// ==========================================
// حقن الـ IP السكني الحقيقي المولّد في جميع اتصالات الشبكة
// ==========================================
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Real-IP"];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"True-Client-IP"];
    return %orig(mutableReq, completionHandler);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Real-IP"];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"True-Client-IP"];
    return %orig(mutableReq);
}

%end

%hook NSURLConnection

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Real-IP"];
    return %orig(mutableReq, response, error);
}

%end

// ==========================================
// تدوير الموقع الجغرافي (CoreLocation - Atlanta)
// ==========================================
%hook CLLocationManager

- (void)startUpdatingLocation {
    %orig;
    CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:currentLatitude longitude:currentLongitude];
    if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
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
// خداع معرفات الجهاز (IDFA & UIDevice)
// ==========================================
%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:currentIDFA];
}

%end

%hook UIDevice

- (NSString *)identifierForVendor {
    return [[NSUUID UUID] UUIDString];
}

%end

// ==========================================
// مراقبة دورة حياة التطبيق وإعادة الضبط
// ==========================================
%ctor {
    @autoreleasepool {
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleIdentifier || ![bundleIdentifier isEqualToString:@"com.codebysms"]) {
            return;
        }
        
        performFullSessionReset();
        
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            performFullSessionReset();
        }];
    }
}
