// ============================================================
// AutoClickerTweak for ESign Injection (No Substrate)
// ============================================================

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach_time.h>

#import <IOKit/hid/IOHIDEvent.h>
#import <IOKit/hid/IOHIDEventTypes.h>
#import <IOKit/hid/IOHIDEventData.h>

// ============================================================
// تصريحات الدوال الخاصة
// ============================================================

@interface UITouch (FakeTouchPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)reset;
- (void)_setIsFirstTouchForView:(BOOL)flag;
- (void)_setIsTapToClick:(BOOL)flag;
- (void)setGestureView:(UIView *)view;
@end

@interface UIApplication (FakeTouchPrivate)
- (UIEvent *)_touchesEvent;
@end

@interface UIEvent (FakeTouchPrivate)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end

// ============================================================
// Helpers
// ============================================================

static inline void AC_SetWindow(id self, id win) {
    if (!self || !win) return;
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setWindow:), win);
}
static inline void AC_SetView(id self, id v) {
    if (!self) return;
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setView:), v);
}
static inline void AC_SetPhase(id self, UITouchPhase p) {
    if (!self) return;
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(self, @selector(setPhase:), (NSInteger)p);
}
static inline void AC_SetTimestamp(id self, NSTimeInterval t) {
    if (!self) return;
    ((void (*)(id, SEL, double))objc_msgSend)(self, @selector(setTimestamp:), t);
}
static inline void AC_SetLocation(id self, CGPoint p, BOOL reset) {
    if (!self) return;
    ((void (*)(id, SEL, CGPoint, BOOL))objc_msgSend)(self,
        @selector(_setLocationInWindow:resetPrevious:), p, reset);
}

// ============================================================
// HID Event
// ============================================================

static IOHIDEventRef AC_CreateHIDEventWithTouches(NSArray *touches) {
    if (!touches || touches.count == 0) return NULL;

    uint64_t abTime = mach_absolute_time();
    AbsoluteTime timeStamp;
    timeStamp.hi = (UInt32)(abTime >> 32);
    timeStamp.lo = (UInt32)(abTime);

    IOHIDEventRef handEvent = NULL;
    @try {
        handEvent = IOHIDEventCreateDigitizerEvent(
            kCFAllocatorDefault, timeStamp, kIOHIDDigitizerTransducerTypeHand,
            0, 0, 0, 0,
            0, 0, 0, 0, 0,
            false, false, 0);
    } @catch (NSException *e) { return NULL; }
    if (!handEvent) return NULL;

    for (NSUInteger i = 0; i < touches.count; i++) {
        UITouch *touch = touches[i];
        if (!touch) continue;

        UITouchPhase phase = touch.phase;
        CGPoint loc = CGPointZero;
        @try {
            UIWindow *w = touch.window;
            if (w) loc = [touch locationInView:w];
        } @catch (NSException *e) { continue; }

        IOHIDEventRef fingerEvent = NULL;
        @try {
            fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(
                kCFAllocatorDefault, timeStamp,
                (uint32_t)(i + 1), 2, 0,
                (IOHIDFloat)loc.x, (IOHIDFloat)loc.y, 0, 0, 0,
                1.0, 1.0, 1.0, 1.0, 0.0,
                false,
                (phase != UITouchPhaseEnded),
                0);
        } @catch (NSException *e) { continue; }

        if (!fingerEvent) continue;
        IOHIDEventAppendEvent(handEvent, fingerEvent);
        CFRelease(fingerEvent);
    }
    return handEvent;
}

// ============================================================
// Touch Factory
// ============================================================

static UITouch *AC_MakeTouch(CGPoint point, UIWindow *window) {
    if (!window) return nil;

    UITouch *touch = nil;
    @try { touch = [[UITouch alloc] init]; }
    @catch (NSException *e) { return nil; }
    if (!touch) return nil;

    @try {
        AC_SetWindow(touch, window);
        AC_SetLocation(touch, point, YES);

        UIView *hitView = [window hitTest:point withEvent:nil];
        AC_SetView(touch, hitView);
        AC_SetPhase(touch, UITouchPhaseBegan);

        if ([touch respondsToSelector:@selector(_setIsFirstTouchForView:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(touch,
                @selector(_setIsFirstTouchForView:), YES);
        }
        if ([touch respondsToSelector:@selector(_setIsTapToClick:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(touch,
                @selector(_setIsTapToClick:), NO);
        }

        AC_SetTimestamp(touch, [[NSProcessInfo processInfo] systemUptime]);

        if ([touch respondsToSelector:@selector(setGestureView:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(touch,
                @selector(setGestureView:), hitView);
        }
    } @catch (NSException *e) { return nil; }
    return touch;
}

// ============================================================
// ZSFakeTouch
// ============================================================

static UITouch *gZSTouch = nil;

@interface ZSFakeTouch : NSObject
+ (void)beginTouchWithPoint:(CGPoint)point;
+ (void)endTouchWithPoint:(CGPoint)point;
+ (BOOL)selfTest;
@end

@implementation ZSFakeTouch

+ (UIWindow *)lastWindow {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;

    UIWindow *keyWin = app.keyWindow;
    if (keyWin) return keyWin;

    NSArray *windows = app.windows;
    for (UIWindow *w in [windows reverseObjectEnumerator]) {
        if ([w isKindOfClass:[UIWindow class]] && !w.hidden) {
            return w;
        }
    }
    return windows.firstObject;
}

+ (UIEvent *)eventWithTouches:(NSArray *)touches {
    if (!touches || touches.count == 0) return nil;

    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;

    UIEvent *event = nil;
    @try {
        if ([app respondsToSelector:@selector(_touchesEvent)]) {
            event = ((UIEvent *(*)(id, SEL))objc_msgSend)(app, @selector(_touchesEvent));
        }
    } @catch (NSException *e) { }

    if (!event) {
        @try { event = [[UIEvent alloc] init]; }
        @catch (NSException *e) { return nil; }
    }
    if (!event) return nil;

    @try {
        if ([event respondsToSelector:@selector(_clearTouches)]) {
            ((void (*)(id, SEL))objc_msgSend)(event, @selector(_clearTouches));
        }

        IOHIDEventRef hid = AC_CreateHIDEventWithTouches(touches);
        if (hid && [event respondsToSelector:@selector(_setHIDEvent:)]) {
            ((void (*)(id, SEL, IOHIDEventRef))objc_msgSend)(event,
                @selector(_setHIDEvent:), hid);
        }
        if (hid) CFRelease(hid);

        for (UITouch *t in touches) {
            if ([event respondsToSelector:@selector(_addTouch:forDelayedDelivery:)]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(event,
                    @selector(_addTouch:forDelayedDelivery:), t, NO);
            }
        }
    } @catch (NSException *e) { return nil; }
    return event;
}

+ (BOOL)selfTest {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return NO;
    UIWindow *win = [self lastWindow];
    if (!win) return NO;
    UITouch *t = AC_MakeTouch(CGPointMake(100, 100), win);
    if (!t) return NO;
    IOHIDEventRef hid = AC_CreateHIDEventWithTouches(@[t]);
    if (!hid) return NO;
    CFRelease(hid);
    return YES;
}

+ (void)beginTouchWithPoint:(CGPoint)point {
    @try {
        UIWindow *window = [self lastWindow];
        if (!window) return;

        UITouch *touch = AC_MakeTouch(point, window);
        if (!touch) return;

        gZSTouch = touch;
        AC_SetPhase(touch, UITouchPhaseBegan);

        UIEvent *event = [self eventWithTouches:@[touch]];
        if (!event) { gZSTouch = nil; return; }

        [[UIApplication sharedApplication] sendEvent:event];

        if (touch.phase == UITouchPhaseBegan ||
            touch.phase == UITouchPhaseMoved) {
            AC_SetPhase(touch, UITouchPhaseStationary);
        }
    } @catch (NSException *e) {
        gZSTouch = nil;
    }
}

+ (void)endTouchWithPoint:(CGPoint)point {
    if (!gZSTouch) return;
    @try {
        AC_SetLocation(gZSTouch, point, NO);
        AC_SetPhase(gZSTouch, UITouchPhaseEnded);
        UIEvent *event = [self eventWithTouches:@[gZSTouch]];
        if (event) [[UIApplication sharedApplication] sendEvent:event];
    } @catch (NSException *e) { }
    gZSTouch = nil;
}

@end

// ============================================================
// AutoClicker Engine
// ============================================================

@interface AutoClickerEngine : NSObject
@property (nonatomic, assign) CGPoint tapPoint;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSTimeInterval interval;
@end

@implementation AutoClickerEngine

+ (instancetype)shared {
    static AutoClickerEngine *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[AutoClickerEngine alloc] init];
        inst.tapPoint = CGPointMake([UIScreen mainScreen].bounds.size.width / 2.0,
                                    [UIScreen mainScreen].bounds.size.height / 2.0);
        inst.interval = 1.5;
        inst.running = NO;
    });
    return inst;
}

- (void)start {
    if (self.running) return;
    self.running = YES;

    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:self.interval
                                        repeats:YES
                                          block:^(NSTimer * _Nonnull t) {
        __strong typeof(weakSelf) s = weakSelf;
        if (!s || !s.running) { [t invalidate]; return; }
        [s tapOnce];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    self.running = NO;
    [self.timer invalidate];
    self.timer = nil;
}

- (void)setInterval:(NSTimeInterval)interval {
    _interval = interval;
    if (self.running) {
        [self.timer invalidate];
        self.timer = nil;
        [self start];
    }
}

- (void)tapOnce {
    CGPoint p = self.tapPoint;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [ZSFakeTouch beginTouchWithPoint:p];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                @try { [ZSFakeTouch endTouchWithPoint:p]; }
                @catch (NSException *e) { }
            });
        } @catch (NSException *e) { }
    });
}

@end

// ============================================================
// Floating Panel
// ============================================================

@interface ACPanel : UIView
@property (nonatomic, strong) UIButton *startStopBtn;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *intervalLbl;
@property (nonatomic, strong) UILabel *statusLbl;
@property (nonatomic, strong) UILabel *pointLbl;
@end

@implementation ACPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.88];
        self.layer.cornerRadius = 14;
        self.layer.borderColor = [UIColor yellowColor].CGColor;
        self.layer.borderWidth = 1.5;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, 204, 22)];
    title.text = @"⚡ Auto Clicker";
    title.textColor = [UIColor yellowColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(188, 4, 26, 22);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:closeBtn];

    self.startStopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.startStopBtn.frame = CGRectMake(10, 34, 200, 34);
    [self.startStopBtn setTitle:@"▶ START" forState:UIControlStateNormal];
    [self.startStopBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.startStopBtn.backgroundColor = [UIColor greenColor];
    self.startStopBtn.layer.cornerRadius = 8;
    self.startStopBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.startStopBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.startStopBtn];

    self.intervalLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 72, 200, 18)];
    self.intervalLbl.text = [NSString stringWithFormat:@"Interval: %.1fs", [AutoClickerEngine shared].interval];
    self.intervalLbl.textColor = [UIColor whiteColor];
    self.intervalLbl.font = [UIFont boldSystemFontOfSize:12];
    self.intervalLbl.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.intervalLbl];

    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(10, 92, 200, 26)];
    self.slider.minimumValue = 1.0;
    self.slider.maximumValue = 10.0;
    self.slider.value = [AutoClickerEngine shared].interval;
    self.slider.continuous = YES;
    self.slider.minimumTrackTintColor = [UIColor yellowColor];
    self.slider.maximumTrackTintColor = [UIColor lightGrayColor];
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:self.slider];

    self.pointLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 118, 200, 16)];
    CGPoint p = [AutoClickerEngine shared].tapPoint;
    self.pointLbl.text = [NSString stringWithFormat:@"Point: %.0f, %.0f", p.x, p.y];
    self.pointLbl.textColor = [UIColor lightGrayColor];
    self.pointLbl.font = [UIFont systemFontOfSize:11];
    self.pointLbl.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.pointLbl];

    UIButton *pickBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    pickBtn.frame = CGRectMake(10, 138, 200, 26);
    [pickBtn setTitle:@"📍 Pick Tap Point" forState:UIControlStateNormal];
    [pickBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    pickBtn.backgroundColor = [UIColor cyanColor];
    pickBtn.layer.cornerRadius = 6;
    pickBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [pickBtn addTarget:self action:@selector(pickPoint) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:pickBtn];

    self.statusLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 168, 200, 16)];
    self.statusLbl.text = @"Status: Idle";
    self.statusLbl.textColor = [UIColor cyanColor];
    self.statusLbl.font = [UIFont systemFontOfSize:11];
    self.statusLbl.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.statusLbl];
}

- (void)sliderChanged:(UISlider *)s {
    NSTimeInterval v = round(s.value * 10.0) / 10.0;
    self.intervalLbl.text = [NSString stringWithFormat:@"Interval: %.1fs", v];
    [AutoClickerEngine shared].interval = v;
    if ([AutoClickerEngine shared].running) {
        self.statusLbl.text = [NSString stringWithFormat:@"Running (%.1fs)", v];
    }
}

- (void)toggle {
    AutoClickerEngine *eng = [AutoClickerEngine shared];
    if (eng.running) {
        [eng stop];
        [self.startStopBtn setTitle:@"▶ START" forState:UIControlStateNormal];
        self.startStopBtn.backgroundColor = [UIColor greenColor];
        self.statusLbl.text = @"Status: Idle";
        self.statusLbl.textColor = [UIColor cyanColor];
    } else {
        [ZSFakeTouch selfTest];
        [eng start];
        [self.startStopBtn setTitle:@"⏸ STOP" forState:UIControlStateNormal];
        self.startStopBtn.backgroundColor = [UIColor redColor];
        self.statusLbl.text = [NSString stringWithFormat:@"Running (%.1fs)", eng.interval];
        self.statusLbl.textColor = [UIColor greenColor];
    }
}

- (void)hide {
    [[AutoClickerEngine shared] stop];
    self.hidden = YES;
}

- (void)pickPoint {
    self.statusLbl.text = @"Tap anywhere...";
    self.statusLbl.textColor = [UIColor orangeColor];

    UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
    if (!keyWin) return;

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handlePick:)];
    [keyWin addGestureRecognizer:tap];
}

- (void)handlePick:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:g.view];
    [AutoClickerEngine shared].tapPoint = p;
    self.pointLbl.text = [NSString stringWithFormat:@"Point: %.0f, %.0f", p.x, p.y];
    self.statusLbl.text = @"Point selected ✔";
    self.statusLbl.textColor = [UIColor greenColor];
    [g.view removeGestureRecognizer:g];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint loc = [t locationInView:self.superview];
    CGPoint prev = [t previousLocationInView:self.superview];
    self.center = CGPointMake(self.center.x + (loc.x - prev.x),
                              self.center.y + (loc.y - prev.y));
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(self.center)
                                              forKey:@"ACPanelCenter"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

// ============================================================
// Method Swizzling يدوي (بدون Substrate)
// ============================================================

static ACPanel *gPanel = nil;
static UIButton *gFloatBtn = nil;

static void AC_ShowPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if (!gPanel) {
                CGRect frame = CGRectMake(20, 120, 220, 192);
                gPanel = [[ACPanel alloc] initWithFrame:frame];

                NSString *saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"ACPanelCenter"];
                if (saved) gPanel.center = CGPointFromString(saved);

                UIWindow *win = [UIApplication sharedApplication].keyWindow;
                if (!win) win = [[[UIApplication sharedApplication] windows] firstObject];
                if (!win) return;
                [win addSubview:gPanel];
            }
            gPanel.hidden = NO;
        } @catch (NSException *e) { }
    });
}

static void AC_AddFloatingButton(UIWindow *window) {
    if (gFloatBtn) return;
    if (!window) return;

    @try {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        CGFloat sw = [UIScreen mainScreen].bounds.size.width;
        btn.frame = CGRectMake(sw - 62, 100, 46, 46);
        btn.layer.cornerRadius = 23;
        btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.55 blue:1.0 alpha:0.9];
        [btn setTitle:@"⚡" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:24];
        btn.layer.borderColor = [UIColor whiteColor].CGColor;
        btn.layer.borderWidth = 1.5;

        [btn addTarget:[NSNull class]
                action:@selector(description)
      forControlEvents:UIControlEventTouchUpInside];

        // استخدم IMP مباشر بدل target/action
        [btn addTarget:(id)objc_getClass("NSObject")
                action:@selector(ac_togglePanel)
      forControlEvents:UIControlEventTouchUpInside];

        // حل بديل: block
        [btn addAction:[UIAction actionWithHandler:^(UIAction *a) {
            if (gPanel && !gPanel.hidden) {
                gPanel.hidden = YES;
            } else {
                AC_ShowPanel();
            }
        }] forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                        initWithTarget:btn action:@selector(removeFromSuperview)];
        [btn addGestureRecognizer:pan];

        [window addSubview:btn];
        gFloatBtn = btn;
    } @catch (NSException *e) { }
}

// --- Swizzling يدوي ---

static IMP original_makeKeyAndVisible = NULL;

static void swizzled_makeKeyAndVisible(UIWindow *self, SEL _cmd) {
    if (original_makeKeyAndVisible) {
        ((void (*)(id, SEL))original_makeKeyAndVisible)(self, _cmd);
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            AC_AddFloatingButton(self);
        });
    });
}

static void AC_InstallSwizzle(void) {
    Class cls = objc_getClass("UIWindow");
    if (!cls) return;

    Method m = class_getInstanceMethod(cls, @selector(makeKeyAndVisible));
    if (!m) return;

    original_makeKeyAndVisible = method_getImplementation(m);
    method_setImplementation(m, (IMP)swizzled_makeKeyAndVisible);
}

// ============================================================
// Constructor — يعمل بدون Substrate
// ============================================================

__attribute__((constructor))
static void AutoClickerInit(void) {
    NSLog(@"[AutoClickerTweak] Loaded ✔ (ESign mode)");

    dispatch_async(dispatch_get_main_queue(), ^{
        AC_InstallSwizzle();
    });
}
