#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <AdSupport/AdSupport.h>
#import <WebKit/WebKit.h>

// تعريف الثوابت الخاصة بمدينة أتلانتا، جورجيا (نطاق جيوغرافي دقيق وعشوائي)
#define ATLANTA_LAT_MIN 33.7489
#define ATLANTA_LAT_MAX 33.7900
#define ATLANTA_LNG_MIN -84.4200
#define ATLANTA_LNG_MAX -84.3800

// متغيرات عامة لتخزين حالة الجلسة الحالية والـ IP الوهمي والموقع
static NSString *currentResidentialIP = nil;
static double currentLatitude = 33.7490;
static double currentLongitude = -84.3880;
static NSString *currentIDFA = nil;

// دالة لتوليد رقم عشوائي ضمن مدى محدد
static double randomInRange(double min, double max) {
    return min + (arc4random_uniform(UINT32_MAX) / (double)UINT32_MAX) * (max - min);
}

// دالة لتوليد IP أمريكي سكني وهمي متجدد
static void rotateResidentialIP(void) {
    int segment2 = arc4random_uniform(50) + 10; // نطاق واقعي
    int segment3 = arc4random_uniform(254) + 1;
    int segment4 = arc4random_uniform(254) + 1;
    currentResidentialIP = [NSString stringWithFormat:@"192.%d.%d.%d", segment2, segment3, segment4];
}

// دالة لتوليد IDFA جديد نظيف
static void rotateIDFA(void) {
    currentIDFA = [[NSUUID UUID] UUIDString];
}

// دالة إعادة ضبط الحالة بالكامل (Fresh Session Reset)
static void performFullSessionReset(void) {
    @autoreleasepool {
        // 1. تدوير الهوية والشبكة
        rotateResidentialIP();
        rotateIDFA();
        
        // 2. تحديث إحداثيات أتلانتا
        currentLatitude = randomInRange(ATLANTA_LAT_MIN, ATLANTA_LAT_MAX);
        currentLongitude = randomInRange(ATLANTA_LNG_MIN, ATLANTA_LNG_MAX);
        
        // 3. مسح NSUserDefaults الخاصة بالتطبيق
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleID isEqualToString:@"com.codebysms"]) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleID];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            // 4. مسح Caches والملفات المؤقتة
            NSString *libraryDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
            NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSArray *cacheContents = [fileManager contentsOfDirectoryAtPath:cacheDir error:nil];
            for (NSString *file in cacheContents) {
                [fileManager removeItemAtPath:[cacheDir stringByAppendingPathComponent:file] error:nil];
            }
            
            // 5. مسح WebKit Data (Cookies / Local Storage)
            if (@available(iOS 9.0, *)) {
                NSSet *websiteDataTypes = [WKWebsiteDataStore-allWebsiteDataTypes];
                [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes 
                                                          modifiedSince:[NSDate distantPast] 
                                                      completionHandler:^{}];
            }
            
            // 6. مسح HTTP Cookies Storage
            NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
                [cookieStorage deleteCookie:cookie];
            }
        }
    }
}

// ==========================================
// 1. حقن الـ IP والترويسات في شبكات NSURLSession / CFNetwork
// ==========================================
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    
    // حقن ترويسات الـ IP السكني الوهمي لتجاوز فحص شبكات الإعلانات
    [mutableReq setValue:currentResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:currentResidentialIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:currentResidentialIP forHTTPHeaderField:@"X-Real-IP"];
    
    return %orig(mutableReq, completionHandler);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    [mutableReq setValue:currentResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:currentResidentialIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:currentResidentialIP forHTTPHeaderField:@"X-Real-IP"];
    
    return %orig(mutableReq);
}

%end

// دعم اتصالات NSURLConnection القديمة إن وجدت
%hook NSURLConnection

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    [mutableReq setValue:currentResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:currentResidentialIP forHTTPHeaderField:@"Client-IP"];
    return %orig(mutableReq, response, error);
}

%end

// ==========================================
// 2. تدوير الموقع الجغرافي (CoreLocation - Atlanta)
// ==========================================
%hook CLLocationManager

- (void)startUpdatingLocation {
    %orig;
    CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:currentLatitude longitude:currentLongitude];
    
    // إرسال الموقع الوهمي المبرمج فوراً للـ Delegate
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
// 3. خداع معرفات الجهاز (IDFA & UIDevice)
// ==========================================
%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:currentIDFA];
}

%end

%hook UIDevice

- (NSString *)identifierForVendor {
    // إرجاع UUID ثابت لكل جلسة مرتبطة
    return [[NSUUID UUID] UUIDString];
}

%end

// ==========================================
// 4. مراقبة دورة حياة التطبيق وإعادة الضبط
// ==========================================
%ctor {
    @autoreleasepool {
        // التحقق من فلترة البندل حصرياً لتطبيق com.codebysms
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (!bundleIdentifier || ![bundleIdentifier isEqualToString:@"com.codebysms"]) {
            return;
        }
        
        // التهيئة الأولية للجلسة الأولى
        performFullSessionReset();
        
        // مراقبة عودة التطبيق من الخلفية لتنفيذ تدوير الجلسة بالكامل
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            performFullSessionReset();
        }];
    }
}
