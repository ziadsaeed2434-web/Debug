// ============================================================
// AutoClickerTweak - Tweak.xm
// يعتمد على نفس منطق الكود الأصلي (ZSFakeTouch + Madness)
// مع إضافة: التحكم بالفاصل الزمني من 1 إلى 10 ثوانٍ
// ============================================================

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <mach/mach_time.h>
#import <ImageIO/ImageIO.h>

// ---------- IOKit (لمحاكاة اللمس الحقيقي) ----------
#import <IOKit/hid/IOHIDEvent.h>
#import <IOKit/hid/IOHIDEventTypes.h>

// دوال خاصة لإنشاء أحداث HID
extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(
    CFAllocatorRef allocator,
    AbsoluteTime timeStamp,
    IOHIDDigitizerTransducerType type,
    uint32_t index,
    uint32_t identity,
    uint32_t eventMask,
    uint32_t buttonMask,
    IOHIDDigitizerEventOptions options,
    IOHIDFloat x, IOHIDFloat y, IOHIDFloat z,
    IOHIDFloat tipPressure, IOHIDFloat barrelPressure,
    Boolean range, Boolean touch, IOOptionBits options2);

extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEventWithQuality(
    CFAllocatorRef allocator,
    AbsoluteTime timeStamp,
    uint32_t index,
    uint32_t identity,
    IOHIDDigitizerTransducerType type,
    IOHIDFloat x, IOHIDFloat y, IOHIDFloat z,
    IOHIDFloat tipPressure, IOHIDFloat twist,
    Boolean range, Boolean touch, Boolean options,
    IOHIDFloat quality, IOHIDFloat density, IOHIDFloat irregularity);

extern void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child);
extern void IOHIDEventSetIntegerValue(IOHIDEventRef event, int field, CFIndex value);

// ثوابت
#ifndef kIOHIDEventFieldIsBuiltIn
#define kIOHIDEventFieldIsBuiltIn 0xB0019
#endif

#pragma mark - ============================================================
#pragma mark UITouch (Fake) - محاكاة اللمس
#pragma mark ============================================================

@interface UITouch (FakeTouch)
- (instancetype)fake_initAtPoint:(CGPoint)point inWindow:(UIWindow *)window;
- (void)fake_setPhaseAndUpdateTimestamp:(UITouchPhase)phase;
- (void)fake_setLocationInWindow:(CGPoint)point;
@end

@implementation UITouch (FakeTouch)

- (instancetype)fake_initAtPoint:(CGPoint)point inWindow:(UIWindow *)window {
    self = [self init];
    if (!self) return nil;

    [self setWindow:window];
    [self _setLocationInWindow:point resetPrevious:YES];

    UIView *hitView = [window hitTest:point withEvent:nil];
    [self setView:hitView];
    [self setPhase:UITouchPhaseBegan];

    if ([self respondsToSelector:NSSelectorFromString(@"_setIsFirstTouchForView:")]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self,
            NSSelectorFromString(@"_setIsFirstTouchForView:"), YES);
    }
    if ([self respondsToSelector:NSSelectorFromString(@"_setIsTapToClick:")]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self,
            NSSelectorFromString(@"_setIsTapToClick:"), NO);
    }

    [self setTimestamp:[[NSProcessInfo processInfo] systemUptime]];

    if ([self respondsToSelector:NSSelectorFromString(@"setGestureView:")]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self,
            NSSelectorFromString(@"setGestureView:"), hitView);
    }

    // إنشاء حدث HID (مطلوب لـ iOS 9+)
    if ([NSProcessInfo instancesRespondToSelector:
            NSSelectorFromString(@"isOperatingSystemAtLeastVersion:")]) {
        // نضبط HID event لاحقاً في eventWithTouches
    }

    return self;
}

- (void)fake_setPhaseAndUpdateTimestamp:(UITouchPhase)phase {
    [self setTimestamp:[[NSProcessInfo processInfo] systemUptime]];
    [self setPhase:phase];
}

- (void)fake_setLocationInWindow:(CGPoint)point {
    [self setTimestamp:[[NSProcessInfo processInfo] systemUptime]];
    [self _setLocationInWindow:point resetPrevious:NO];
}

@end

#pragma mark - ============================================================
#pragma mark UIEvent (Fake) - بناء الأحداث
#pragma mark ============================================================

static IOHIDEventRef AC_IOHIDEventWithTouches(NSArray *touches) {
    uint64_t abTime = mach_absolute_time();
    AbsoluteTime timeStamp = *(AbsoluteTime *)&abTime;

    IOHIDEventRef handEvent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        timeStamp,
        0, 0, 0, 0, 0, 0,           // type, index, identity, masks, options
        0, 0, 0, 0, 0, 0, 0, 0);    // coordinates/pressure
    IOHIDEventSetIntegerValue(handEvent, kIOHIDEventFieldIsBuiltIn, 1);

    for (NSUInteger i = 0; i < touches.count; i++) {
        UITouch *touch = touches[i];
        UITouchPhase phase = touch.phase;

        uint32_t fingerMask = 3; // default
        if (phase == UITouchPhaseBegan)   fingerMask = 4;
        else if (phase == UITouchPhaseMoved) fingerMask = 3;
        else if (phase == UITouchPhaseEnded) fingerMask = 3;

        CGPoint loc = [touch locationInView:touch.window];

        IOHIDEventRef fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(
            kCFAllocatorDefault,
            timeStamp,
            (uint32_t)(i + 1),       // index
            2,                        // identity
            0,                        // type
            (IOHIDFloat)loc.x,
            (IOHIDFloat)loc.y,
            0, 0, 0,
            0,
            (phase != UITouchPhaseEnded), // touch
            (phase != UITouchPhaseEnded),
            0,
            1.0, 1.0, 0);

        IOHIDEventSetIntegerValue(fingerEvent, kIOHIDEventFieldIsBuiltIn, 1);
        IOHIDEventAppendEvent(handEvent, fingerEvent);
        CFRelease(fingerEvent);
    }
    return handEvent;
}

@interface UIEvent (FakeTouch)
- (void)fake_setEventWithTouches:(NSArray *)touches;
@end

@implementation UIEvent (FakeTouch)

- (void)fake_setEventWithTouches:(NSArray *)touches {
    IOHIDEventRef hidEvent = AC_IOHIDEventWithTouches(touches);
    ((void (*)(id, SEL, IOHIDEventRef))objc_msgSend)(self,
        NSSelectorFromString(@"_setHIDEvent:"), hidEvent);
    CFRelease(hidEvent);
}

@end

#pragma mark - ============================================================
#pragma mark ZSFakeTouch - الفئة الأساسية لمحاكاة اللمس
#pragma mark ============================================================

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
    UIEvent *event = [[UIApplication sharedApplication] _touchesEvent];
    [event _clearTouches];
    [event fake_setEventWithTouches:touches];
    for (UITouch *t in touches) {
        [event _addTouch:t forDelayedDelivery:NO];
    }
    return event;
}

+ (void)beginTouchWithPoint:(CGPoint)point {
    UIWindow *window = [self lastWindow];

    UITouch *touch = [[UITouch alloc] fake_initAtPoint:point inWindow:window];
    gZSTouch = touch;
    [touch fake_setPhaseAndUpdateTimestamp:UITouchPhaseBegan];

    UIEvent *event = [self eventWithTouches:@[touch]];
    [[UIApplication sharedApplication] sendEvent:event];

    if (touch.phase == UITouchPhaseBegan ||
        touch.phase == UITouchPhaseMoved) {
        [touch fake_setPhaseAndUpdateTimestamp:UITouchPhaseStationary];
    }
}

+ (void)moveTouchWithPoint:(CGPoint)point {
    if (!gZSTouch) return;
    [gZSTouch fake_setLocationInWindow:point];
    [gZSTouch fake_setPhaseAndUpdateTimestamp:UITouchPhaseMoved];

    UIEvent *event = [self eventWithTouches:@[gZSTouch]];
    [[UIApplication sharedApplication] sendEvent:event];
    [gZSTouch fake_setPhaseAndUpdateTimestamp:UITouchPhaseStationary];
}

+ (void)endTouchWithPoint:(CGPoint)point {
    if (!gZSTouch) return;
    [gZSTouch fake_setLocationInWindow:point];
    [gZSTouch fake_setPhaseAndUpdateTimestamp:UITouchPhaseEnded];

    UIEvent *event = [self eventWithTouches:@[gZSTouch]];
    [[UIApplication sharedApplication] sendEvent:event];
    gZSTouch = nil;
}

@end

#pragma mark - ============================================================
#pragma mark AutoClicker Engine
#pragma mark ============================================================

@interface AutoClickerEngine : NSObject
@property (nonatomic, assign) CGPoint tapPoint;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSTimeInterval interval;  // 1.0 - 10.0 sec
@end

@implementation AutoClickerEngine

+ (instancetype)shared {
    static AutoClickerEngine *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[AutoClickerEngine alloc] init];
        inst.tapPoint = CGPointMake([UIScreen mainScreen].bounds.size.width / 2.0,
                                    [UIScreen mainScreen].bounds.size.height / 2.0);
        // القيمة الافتراضية = 1.5 ثانية (نفس القيمة الأصلية في الكود المستخرج)
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

#pragma mark - ============================================================
#pragma mark Floating UI Panel
#pragma mark ============================================================

@interface ACPanel : UIView
@property (nonatomic, strong) UIButton *startStopBtn;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *intervalLbl;
@property (nonatomic, strong) UILabel *statusLbl;
@property (nonatomic, strong) UILabel *pointLbl;
@property (nonatomic, assign) BOOL selectingPoint;
@end

@implementation ACPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.88];
        self.layer.cornerRadius = 14;
        self.layer.borderColor = [UIColor yellowColor].CGColor;
        self.layer.borderWidth = 1.5;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.7;
        self.layer.shadowRadius = 6;
        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    // العنوان
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, 204, 22)];
    title.text = @"⚡ Auto Clicker Pro";
    title.textColor = [UIColor yellowColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];

    // زر إغلاق
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(188, 4, 26, 22);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:closeBtn];

    // زر START/STOP
    self.startStopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.startStopBtn.frame = CGRectMake(10, 34, 200, 34);
    [self.startStopBtn setTitle:@"▶ START" forState:UIControlStateNormal];
    [self.startStopBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.startStopBtn.backgroundColor = [UIColor greenColor];
    self.startStopBtn.layer.cornerRadius = 8;
    self.startStopBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.startStopBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.startStopBtn];

    // ملصق الفاصل
    self.intervalLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 72, 200, 18)];
    self.intervalLbl.text = @"Interval: 1.5s";
    self.intervalLbl.textColor = [UIColor whiteColor];
    self.intervalLbl.font = [UIFont boldSystemFontOfSize:12];
    self.intervalLbl.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.intervalLbl];

    // سلايدر الفاصل من 1 إلى 10 ثوان
    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(10, 92, 200, 26)];
    self.slider.minimumValue = 1.0;
    self.slider.maximumValue = 10.0;
    self.slider.value = [AutoClickerEngine shared].interval;
    self.slider.continuous = YES;
    self.slider.minimumTrackTintColor = [UIColor yellowColor];
    self.slider.maximumTrackTintColor = [UIColor lightGrayColor];
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:self.slider];

    // ملصق النقطة الحالية
    self.pointLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 118, 200, 16)];
    CGPoint p = [AutoClickerEngine shared].tapPoint;
    self.pointLbl.text = [NSString stringWithFormat:@"Point: %.0f, %.0f", p.x, p.y];
    self.pointLbl.textColor = [UIColor lightGrayColor];
    self.pointLbl.font = [UIFont systemFontOfSize:11];
    self.pointLbl.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.pointLbl];

    // زر اختيار النقطة
    UIButton *pickBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    pickBtn.frame = CGRectMake(10, 138, 200, 26);
    [pickBtn setTitle:@"📍 Pick Tap Point" forState:UIControlStateNormal];
    [pickBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    pickBtn.backgroundColor = [UIColor cyanColor];
    pickBtn.layer.cornerRadius = 6;
    pickBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [pickBtn addTarget:self action:@selector(pickPoint) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:pickBtn];

    // ملصق الحالة
    self.statusLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 168, 200, 16)];
    self.statusLbl.text = @"Status: Idle";
    self.statusLbl.textColor = [UIColor cyanColor];
    self.statusLbl.font = [UIFont systemFontOfSize:11];
    self.statusLbl.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.statusLbl];
}

#pragma mark - Actions

- (void)sliderChanged:(UISlider *)s {
    NSTimeInterval v = s.value;
    // تدوير لأقرب 0.1
    v = round(v * 10.0) / 10.0;
    self.intervalLbl.text = [NSString stringWithFormat:@"Interval: %.1fs", v];
    [AutoClickerEngine shared].interval = v;

    if ([AutoClickerEngine shared].running) {
        self.statusLbl.text = [NSString stringWithFormat:@"Status: Running (%.1fs)", v];
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
        self.statusLbl.text = [NSString stringWithFormat:@"Status: Running (%.1fs)", eng.interval];
        self.statusLbl.textColor = [UIColor greenColor];
    }
}

- (void)hide {
    [[AutoClickerEngine shared] stop];
    self.hidden = YES;
}

- (void)pickPoint {
    self.selectingPoint = YES;
    self.statusLbl.text = @"Tap anywhere on screen...";
    self.statusLbl.textColor = [UIColor orangeColor];

    UIWindow *keyWin = [[UIApplication sharedApplication] keyWindow];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handlePick:)];
    tap.numberOfTapsRequired = 1;
    [keyWin addGestureRecognizer:tap];
}

- (void)handlePick:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:g.view];
    [AutoClickerEngine shared].tapPoint = p;
    self.pointLbl.text = [NSString stringWithFormat:@"Point: %.0f, %.0f", p.x, p.y];
    self.statusLbl.text = @"Point selected ✔";
    self.statusLbl.textColor = [UIColor greenColor];
    self.selectingPoint = NO;
    [g.view removeGestureRecognizer:g];
}

#pragma mark - Drag Panel

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint loc = [t locationInView:self.superview];
    CGPoint prev = [t previousLocationInView:self.superview];
    self.center = CGPointMake(self.center.x + (loc.x - prev.x),
                              self.center.y + (loc.y - prev.y));
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // حفظ الموقع
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(self.center)
                                              forKey:@"ACPanelCenter"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

#pragma mark - ============================================================
#pragma mark Tweak Hooks
#pragma mark ============================================================

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
            if (!win) {
                win = [[[UIApplication sharedApplication] windows] firstObject];
            }
            [win addSubview:gPanel];
        }
        gPanel.hidden = NO;
    });
}

static void AC_HidePanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gPanel) gPanel.hidden = YES;
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
            btn.layer.shadowColor = [UIColor blackColor].CGColor;
            btn.layer.shadowOpacity = 0.6;
            btn.layer.shadowRadius = 5;

            [btn addTarget:self
                    action:@selector(ac_togglePanel)
          forControlEvents:UIControlEventTouchUpInside];

            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
                                            initWithTarget:self
                                                    action:@selector(ac_panBtn:)];
            [btn addGestureRecognizer:pan];

            [self addSubview:btn];
            gFloatBtn = btn;
        });
    });
}

- (void)ac_togglePanel {
    if (gPanel && !gPanel.hidden) {
        AC_HidePanel();
    } else {
        AC_ShowPanel();
    }
}

- (void)ac_panBtn:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    g.view.center = CGPointMake(g.view.center.x + t.x, g.view.center.y + t.y);
    [g setTranslation:CGPointZero inView:self];

    if (g.state == UIGestureRecognizerStateEnded) {
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(g.view.center)
                                                  forKey:@"ACBtnCenter"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

%end

#pragma mark - ============================================================
#pragma mark Init
#pragma mark ============================================================

%ctor {
    NSLog(@"[AutoClickerTweak] Loaded ✔  — Interval: 1.0s → 10.0s");
}
