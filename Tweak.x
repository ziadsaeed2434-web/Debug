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

static void generateAtlantaResidentialIP(void) {
    @autoreleasepool {
        if (!atlantaResidentialSubnets) {
            atlantaResidentialSubnets = @[
                @{@"prefix": @"73.140."},   
                @{@"prefix": @"67.160."},   
                @{@"prefix": @"104.128."}, 
                @{@"prefix": @"24.98."},   
                @{@"prefix": @"50.130."}    
            ];
        }
        
        NSDictionary *subnetInfo = atlantaResidentialSubnets[arc4random_uniform((uint32_t)[atlantaResidentialSubnets count])];
        NSString *prefix = subnetInfo[@"prefix"];
        
        int thirdOctet = arc4random_uniform(254) + 1;
        int fourthOctet = arc4random_uniform(254) + 1;
        
        currentAtlantaResidentialIP = [NSString stringWithFormat:@"%@%d.%d", prefix, thirdOctet, fourthOctet];
        currentIDFA = [[NSUUID UUID] UUIDString];
        currentLatitude = randomInRange(ATLANTA_LAT_MIN, ATLANTA_LAT_MAX);
        currentLongitude = randomInRange(ATLANTA_LNG_MIN, ATLANTA_LNG_MAX);
    }
}

// ==========================================
// 1. حقن الـ IP السكني في طلبات الشبكة بأمان
// ==========================================
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    if (currentAtlantaResidentialIP) {
        NSMutableURLRequest *mutableReq = [request mutableCopy];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Forwarded-For"];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"Client-IP"];
        [mutableReq setValue:currentAtlantaResidentialIP forHTTPHeaderField:@"X-Real-IP"];
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
        return %orig(mutableReq);
    }
    return %orig(request);
}

%end

// ==========================================
// 2. تدوير الموقع الجغرافي (أتلانتا)
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
// 3. خداع المعرفات
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
// 4. نقطة الحقن العامة الآمنة
// ==========================================
%ctor {
    @autoreleasepool {
        // توليد البيانات الأولية بصمت تام ودون مسح أي ملفات قد تثير حماية التطبيق
        generateAtlantaResidentialIP();
    }
}
