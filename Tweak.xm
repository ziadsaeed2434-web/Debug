// ============================================================
// AutoClickerTweak - Tweak.xm  (FINAL STABLE VERSION)
// ============================================================

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <mach/mach_time.h>

// IOKit — التعريفات الرسمية من Theos
#import <IOKit/hid/IOHIDEvent.h>
#import <IOKit/hid/IOHIDEventTypes.h>
#import <IOKit/hid/IOHIDEventData.h>

// ثوابت احتياطية
#ifndef kIOHIDEventFieldIsBuiltIn
#define kIOHIDEventFieldIsBuiltIn (IOHIDEventField)0xB0019
#endif

// ============================================================
// تصريحات الدوال الخاصة (بدون @implementation لتجنب Werror)
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
// Helper: safe objc_msgSend
// ============================================================

static inline void AC_SetWindow(id self, id win) {
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setWindow:), win);
}
static inline void AC_SetView(id self, id v) {
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(setView:), v);
}
static inline void AC_SetPhase(id self, UITouchPhase p) {
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(self, @selector(setPhase:), (NSInteger)p);
}
static inline void AC_SetTimestamp(id self, NSTimeInterval t) {
    ((void (*)(id, SEL, double))objc_msgSend)(self, @selector(setTimestamp:), t);
}
static inline void AC_SetLocation(id self, CGPoint p, BOOL reset) {
    ((void (*)(id, SEL, CGPoint, BOOL))objc_msgSend)(self, @selector(_setLocationInWindow:resetPrevious:), p, reset);
}
static inline void AC_SetBool(id self, SEL sel, BOOL flag) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, sel, flag);
}

// ============================================================
// إنشاء حدث HID
// ============================================================

static IOHIDEventRef AC_CreateHIDEventWithTouches(NSArray *touches) {
    uint64_t abTime = mach_absolute_time();
    AbsoluteTime timeStamp;
    timeStamp.hi = (UInt32)(abTime >> 32);
    timeStamp.lo = (UInt32)(abTime);

    IOHIDEventRef handEvent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        timeStamp,
        kIOHIDDigitizerTransducerTypeHand,
        0, 0, 0, 0,
        0, 0, 0,
        0, 0,
        false, false,
        0);

    if (!handEvent) return NULL;

    for (NSUInteger i = 0; i < touches.count; i++) {
        UITouch *touch = touches[i];
        UITouchPhase phase = touch.phase;
        CGPoint loc = [touch locationInView:touch.window];

        IOHIDEventRef fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(
            kCFAllocatorDefault,
            timeStamp,
            (uint32_t)(i + 1),
            2,
            0,
            (IOHIDFloat)loc.x,
            (IOHIDFloat)loc.y,
            0, 0, 0,
            1.0, 1.0,
            1.0, 1.0, 0.0,
            false,
            (phase != UITouchPhaseEnded),
            0);

        if (!fingerEvent) continue;
        IOHIDEventAppendEvent(handEvent, fingerEvent);
        CFRelease(fingerEvent);
    }
    return handEvent;
}

// ============================================================
// UITouch Factory
// ============================================================

static UITouch *AC_MakeTouch(CGPoint point, UIWindow *window) {
    UITouch *touch = [[UITouch alloc] init];
    if (!touch) return nil;

    AC_SetWindow(touch, window);
    AC_SetLocation(touch, point, YES);

    UIView *hitView = [window hitTest:point withEvent:nil];
    AC_SetView(touch, hitView);
    AC_SetPhase(touch, UITouchPhaseBegan);

    if ([touch respondsToSelector:@selector(_setIsFirstTouchForView:)]) {
        AC_SetBool(touch, @selector(_setIsFirstTouchForView:), YES);
    }
    if ([touch respondsToSelector:@selector(_setIsTapToClick:)]) {
        AC_SetBool(touch, @selector(_setIsTapToClick:), NO);
    }

    AC_SetTimestamp(touch, [[NSProcessInfo processInfo] systemUptime]);

    if ([touch respondsToSelector:@selector(setGestureView:)]) {
        AC_SetView(touch, hitView);
    }
    return touch;
}

static void AC_UpdateTouch(UITouch *touch, CGPoint point, UITouchPhase phase) {
    AC_SetTimestamp(touch, [[NSProcessInfo processInfo] systemUptime]);
    AC_SetLocation(touch, point, NO);
    AC_SetPhase(touch, phase);
}

// ============================================================
// ZSFakeTouch
// ============================================================

static UITouch *gZSTouch = nil;

@interface ZSFakeTouch : NSObject
+ (void)beginTouchWithPoint:(CGPoint)point;
+ (void)moveTouchWithPoint:(CGPoint)point;
+ (void)endTouchWithPoint:(CGPoint)point;
@end

@implementation ZSFakeTouch

+ (UIWindow *)lastWindow {
    NSArray *windows = [[UIApplication sharedApplication] windows];
    for (UIWindow *w in [windows reverseObjectEnumerator]) {
        if ([w isKindOfClass:[UIWindow class]] &&
            CGRectEqualToRect(w.bounds, [UIScreen mainScreen].bounds)) {
            return w;
        }
    }
    return [[UIApplication sharedApplication] keyWindow];
}

+ (UIEvent *)eventWithTouches:(NSArray *)touches {
    UIApplication *app = [UIApplication sharedApplication];
    UIEvent *event = ((UIEvent *(*)(id, SEL))objc_msgSend)(app, @selector(_touchesEvent));
    ((void (*)(id, SEL))objc_msgSend)(event, @selector(_clearTouches));

    IOHIDEventRef hid = AC_CreateHIDEventWithTouches(touches);
    if (hid) {
        ((void (*)(id, SEL, IOHIDEventRef))objc_msgSend)(event, @selector(_setHIDEvent:), hid);
        CFRelease(hid);
    }

    for (UITouch *t in touches) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(event,
            @selector(_addTouch:forDelayedDelivery:), t, NO);
    }
    return event;
}

+ (void)beginTouchWithPoint:(CGPoint)point {
    UIWindow *window = [self lastWindow];
    if (!window) return;

    UITouch *touch = AC_MakeTouch(point, window);
    gZSTouch = touch;
    AC_SetPhase(touch, UITouchPhaseBegan);

    UIEvent *event = [self eventWithTouches:@[touch]];
    [[UIApplication sharedApplication] sendEvent:event];

    if (touch.phase == UITouchPhaseBegan ||
        touch.phase == UITouchPhaseMoved) {
        AC_SetPhase(touch, UITouchPhaseStationary);
    }
}

+ (void)moveTouchWithPoint:(CGPoint)point {
    if (!gZSTouch) return;
    AC_UpdateTouch(gZSTouch, point, UITouchPhaseMoved);
    UIEvent *event = [self eventWithTouches:@[gZSTouch]];
    [[UIApplication sharedApplication] sendEvent:event];
    AC_SetPhase(gZSTouch, UITouchPhaseStationary);
}

+ (void)endTouchWithPoint:(CGPoint)point {
    if (!gZSTouch) return;
    AC_UpdateTouch(gZSTouch, point, UITouchPhaseEnded);
    UIEvent *event = [self eventWithTouches:@[gZSTouch]];
    [[UIApplication sharedApplication] sendEvent:event];
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
    [self scheduleTimer];
}

- (void)scheduleTimer {
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.interval
                                                 repeats:YES
                                                   block:^(NSTimer * _Nonnull t) {
        [weakSelf tapOnce];
    }];
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
        [self scheduleTimer];
    }
}

- (void)tapOnce {
    CGPoint p = self.tapPoint;
    dispatch_async(dispatch_get_main_queue(), ^{
        [ZSFakeTouch beginTouchWithPoint:p];
        [ZSFakeTouch endTouchWithPoint:p];
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

    UIWindow *keyWin = [[UIApplication sharedApplication] keyWindow];
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
// Hooks
// ============================================================

static ACPanel *gPanel = nil;
static UIButton *gFloatBtn = nil;

static void AC_ShowPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gPanel) {
            CGRect frame = CGRectMake(20, 120, 220, 192);
            gPanel = [[ACPanel alloc] initWithFrame:frame];

            NSString *saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"ACPanelCenter"];
            if (saved) gPanel.center = CGPointFromString(saved);

            UIWindow *win = [[UIApplication sharedApplication] keyWindow];
            if (!win) win = [[[UIApplication sharedApplication] windows] firstObject];
            [win addSubview:gPanel];
        }
        gPanel.hidden = NO;
    });
}

%hook UIWindow

- (void)makeKeyAndVisible {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (gFloatBtn) return;

            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            CGFloat sw = [UIScreen mainScreen].bounds.size.width;
            btn.frame = CGRectMake(sw - 62, 100, 46, 46);
            btn.layer.cornerRadius = 23;
            btn.backgroundColor = [UIColor colorWithRed:0.0 green:0.55 blue:1.0 alpha:0.9];
            [btn setTitle:@"⚡" forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont systemFontOfSize:24];
            btn.layer.borderColor = [UIColor whiteColor].CGColor;
            btn.layer.borderWidth = 1.5;

            [btn addTarget:self action:@selector(ac_togglePanel)
          forControlEvents:UIControlEventTouchUpInside];

            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                            initWithTarget:self action:@selector(ac_panBtn:)];
            [btn addGestureRecognizer:pan];

            [self addSubview:btn];
            gFloatBtn = btn;
        });
    });
}

- (void)ac_togglePanel {
    if (gPanel && !gPanel.hidden) {
        gPanel.hidden = YES;
    } else {
        AC_ShowPanel();
    }
}

- (void)ac_panBtn:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    g.view.center = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    [g setTranslation:CGPointZero inView:self];
}

%end

// ============================================================
// Init
// ============================================================

%ctor {
    NSLog(@"[AutoClickerTweak] Loaded ✔ Interval 1.0s → 10.0s");
}
