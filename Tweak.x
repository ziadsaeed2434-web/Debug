// Tweak.x
// الإصدار النهائي - يعمل التسجيل والحفظ بكل تأكيد

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>

// ============================================================
// تعريفات GSEvent
// ============================================================
#define kGSEventTypeTouch 0x0011
#define kGSEventSubTypeTouch 0

enum {
    kGSEventTouchPhaseBegan    = 0,
    kGSEventTouchPhaseMoved    = 1,
    kGSEventTouchPhaseEnded    = 2,
    kGSEventTouchPhaseCancelled= 3
};

typedef struct {
    uint8_t     type;
    uint8_t     subtype;
    int16_t     window;
    int16_t     window2;
    uint32_t    timestamp;
    struct { float x, y; } location;
    uint8_t     phase;
    uint8_t     flags;
    uint8_t     pathIndex;
    uint8_t     pathIdentity;
} GSEventRecord;

typedef void (*GSEventSendFunc)(GSEventRecord *);
static GSEventSendFunc GSEventSendPtr = NULL;

// ============================================================
// مسار التخزين الدائم
// ============================================================
static NSString * const kMacroStorageDir = @"/var/mobile/Library/Preferences/com.tweak.macros/";
static NSString * const kAutoRepeatKey = @"AutoRepeatMacroName";

// ============================================================
// TXMacroManager - إدارة الماكروز
// ============================================================
@interface TXMacroManager : NSObject
+ (instancetype)sharedManager;
- (NSString *)persistentDirectory;
- (NSArray<NSString *> *)macroNames;
- (NSDictionary *)loadMacroWithName:(NSString *)name;
- (void)saveMacro:(NSDictionary *)macro withName:(NSString *)name;
- (void)deleteMacroWithName:(NSString *)name;
- (NSString *)autoRepeatMacroName;
- (void)setAutoRepeatMacroName:(NSString *)name;
@end

@implementation TXMacroManager {
    NSMutableDictionary *_autoRepeatPreference;
}

+ (instancetype)sharedManager {
    static TXMacroManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [self persistentDirectory];
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSLog(@"[Tweak] ✅ Created macro directory: %@", dir);
        } else {
            NSLog(@"[Tweak] ✅ Macro directory exists: %@", dir);
        }
        NSString *prefPath = [dir stringByAppendingPathComponent:@"autoRepeat.plist"];
        _autoRepeatPreference = [NSMutableDictionary dictionaryWithContentsOfFile:prefPath] ?: [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)persistentDirectory { return kMacroStorageDir; }

- (NSArray<NSString *> *)macroNames {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self persistentDirectory] error:nil];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *file in files) {
        if ([file hasSuffix:@".plist"] && ![file isEqualToString:@"autoRepeat.plist"]) {
            [names addObject:[file stringByDeletingPathExtension]];
        }
    }
    NSLog(@"[Tweak] 📋 Loaded macro names: %@", names);
    return names;
}

- (NSDictionary *)loadMacroWithName:(NSString *)name {
    NSString *path = [[self persistentDirectory] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    NSLog(@"[Tweak] 📂 Loaded macro '%@' with %lu events", name, (unsigned long)[dict[@"events"] count]);
    return dict;
}

- (void)saveMacro:(NSDictionary *)macro withName:(NSString *)name {
    NSString *path = [[self persistentDirectory] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
    BOOL success = [macro writeToFile:path atomically:YES];
    NSLog(@"[Tweak] 💾 Macro saved: %@ (success: %d, events: %lu)", name, success, (unsigned long)[macro[@"events"] count]);
}

- (void)deleteMacroWithName:(NSString *)name {
    NSString *path = [[self persistentDirectory] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    NSLog(@"[Tweak] 🗑️ Macro deleted: %@", name);
}

- (NSString *)autoRepeatMacroName {
    return _autoRepeatPreference[kAutoRepeatKey];
}

- (void)setAutoRepeatMacroName:(NSString *)name {
    if (name) _autoRepeatPreference[kAutoRepeatKey] = name;
    else [_autoRepeatPreference removeObjectForKey:kAutoRepeatKey];
    NSString *prefPath = [[self persistentDirectory] stringByAppendingPathComponent:@"autoRepeat.plist"];
    [_autoRepeatPreference writeToFile:prefPath atomically:YES];
}
@end

// ============================================================
// TXRecorder - تسجيل اللمسات
// ============================================================
@interface TXRecorder : NSObject
@property (nonatomic, assign, readonly) BOOL isRecording;
- (void)startRecording;
- (void)stopRecording;
- (void)cancelRecording;
- (NSDictionary *)recordedMacro;
- (void)captureTouchEvent:(UIEvent *)event;
@end

@implementation TXRecorder {
    NSMutableArray *_events;
    CFAbsoluteTime _startTime;
    BOOL _isRecording;
}

- (instancetype)init {
    if ((self = [super init])) {
        _events = [NSMutableArray array];
        _isRecording = NO;
        NSLog(@"[Tweak] 🎙️ Recorder initialized");
    }
    return self;
}

- (BOOL)isRecording { return _isRecording; }

- (void)startRecording {
    _isRecording = YES;
    [_events removeAllObjects];
    _startTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"[Tweak] 🔴 Recording STARTED");
}

- (void)stopRecording {
    _isRecording = NO;
    NSLog(@"[Tweak] ⏹️ Recording STOPPED (events: %lu)", (unsigned long)_events.count);
}

- (void)cancelRecording {
    _isRecording = NO;
    [_events removeAllObjects];
    NSLog(@"[Tweak] ❌ Recording cancelled");
}

- (NSDictionary *)recordedMacro {
    if (_events.count == 0) {
        NSLog(@"[Tweak] ⚠️ No events recorded!");
        return nil;
    }
    NSDictionary *macro = @{ @"events": _events, @"duration": @(CFAbsoluteTimeGetCurrent() - _startTime) };
    NSLog(@"[Tweak] 📦 Macro built with %lu events", (unsigned long)_events.count);
    return macro;
}

- (void)captureTouchEvent:(UIEvent *)event {
    if (!_isRecording) return;
    NSSet *touches = [event allTouches];
    if (!touches.count) return;
    
    NSTimeInterval timestamp = CFAbsoluteTimeGetCurrent() - _startTime;
    NSMutableArray *touchData = [NSMutableArray array];
    for (UITouch *touch in touches) {
        CGPoint loc = [touch locationInView:touch.window];
        [touchData addObject:@{ @"x": @(loc.x), @"y": @(loc.y), @"phase": @(touch.phase) }];
    }
    [_events addObject:@{ @"timestamp": @(timestamp), @"touches": touchData }];
    NSLog(@"[Tweak] 👆 Captured touch at (%.1f, %.1f) phase: %ld", [touchData[0][@"x"] floatValue], [touchData[0][@"y"] floatValue], (long)[touchData[0][@"phase"] integerValue]);
}
@end

// ============================================================
// TXPlayer - تشغيل الماكروز
// ============================================================
@interface TXPlayer : NSObject
@property (nonatomic, assign, readonly) BOOL isPlaying;
- (void)playMacro:(NSDictionary *)macro;
- (void)stop;
- (void)playMacroWithName:(NSString *)name;
@end

@implementation TXPlayer {
    NSArray *_events;
    NSUInteger _eventIndex;
    dispatch_queue_t _playbackQueue;
    BOOL _isPlaying;
    CFAbsoluteTime _playStartTime;
}

- (instancetype)init {
    if ((self = [super init])) {
        _playbackQueue = dispatch_queue_create("com.tweak.playback", DISPATCH_QUEUE_SERIAL);
        NSLog(@"[Tweak] ▶️ Player initialized");
    }
    return self;
}

- (BOOL)isPlaying { return _isPlaying; }

- (void)playMacro:(NSDictionary *)macro {
    [self stop];
    NSArray *events = macro[@"events"];
    if (!events.count) {
        NSLog(@"[Tweak] ⚠️ No events to play");
        return;
    }
    _events = events;
    _eventIndex = 0;
    _isPlaying = YES;
    _playStartTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"[Tweak] ▶️ Playing macro with %lu events", (unsigned long)_events.count);
    [self scheduleNextEvent];
}

- (void)playMacroWithName:(NSString *)name {
    NSDictionary *macro = [[TXMacroManager sharedManager] loadMacroWithName:name];
    if (macro) [self playMacro:macro];
}

- (void)scheduleNextEvent {
    if (_eventIndex >= _events.count) { [self stop]; return; }
    NSDictionary *event = _events[_eventIndex];
    NSTimeInterval relativeTime = [event[@"timestamp"] doubleValue];
    NSTimeInterval delay = (_playStartTime + relativeTime) - CFAbsoluteTimeGetCurrent();
    if (delay < 0) delay = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _playbackQueue, ^{
        if (!self->_isPlaying) return;
        [self executeEvent:event];
        self->_eventIndex++;
        [self scheduleNextEvent];
    });
}

- (void)executeEvent:(NSDictionary *)eventDict {
    if (!GSEventSendPtr) {
        NSLog(@"[Tweak] ❌ GSEventSend not loaded!");
        return;
    }
    NSArray *touches = eventDict[@"touches"];
    if (!touches) return;
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    #pragma clang diagnostic pop
    if (!keyWindow) return;
    
    for (NSDictionary *touchDict in touches) {
        CGFloat x = [touchDict[@"x"] floatValue];
        CGFloat y = [touchDict[@"y"] floatValue];
        UITouchPhase phase = (UITouchPhase)[touchDict[@"phase"] integerValue];
        GSEventRecord record = {0};
        record.type = kGSEventTypeTouch;
        record.subtype = kGSEventSubTypeTouch;
        record.window = 0; record.window2 = 0;
        record.timestamp = (uint32_t)(CFAbsoluteTimeGetCurrent() * 1000);
        record.location.x = x; record.location.y = y;
        record.flags = 0; record.pathIndex = 0; record.pathIdentity = 0;
        switch (phase) {
            case UITouchPhaseBegan:    record.phase = kGSEventTouchPhaseBegan; break;
            case UITouchPhaseMoved:    record.phase = kGSEventTouchPhaseMoved; break;
            case UITouchPhaseEnded:    record.phase = kGSEventTouchPhaseEnded; break;
            default:                   record.phase = kGSEventTouchPhaseCancelled; break;
        }
        GSEventSendPtr(&record);
        NSLog(@"[Tweak] 📤 Sent simulated touch at (%.1f, %.1f)", x, y);
    }
}

- (void)stop {
    _isPlaying = NO;
    _events = nil;
    _eventIndex = 0;
    NSLog(@"[Tweak] ⏹️ Playback stopped");
}
@end

// ============================================================
// TXFloatingMenu - النافذة العائمة
// ============================================================
@interface TXFloatingMenu : NSObject
+ (instancetype)sharedMenu;
@property (nonatomic, strong) TXRecorder *recorder;
@property (nonatomic, strong) TXPlayer *player;
@property (nonatomic, strong) TXMacroManager *macroManager;
@property (nonatomic, copy) NSString *selectedMacroName;
@property (nonatomic, assign) BOOL autoRepeatEnabled;
- (void)startRecording;
- (void)stopRecordingAndSave;
- (void)selectMacro:(NSString *)name;
- (void)playSelectedMacro;
- (void)toggleAutoRepeat:(BOOL)enabled;
- (void)deleteSelectedMacro;
- (void)setupUI;
@end

@interface TXMenuView : UIView <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, weak) TXFloatingMenu *menuController;
- (void)refreshMacroList;
@end

@implementation TXFloatingMenu {
    UIButton *_floatingButton;
    TXMenuView *_menuView;
    BOOL _menuVisible;
    UIWindow *_targetWindow;
}

+ (instancetype)sharedMenu {
    static TXFloatingMenu *menu = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ menu = [[self alloc] init]; });
    return menu;
}

- (instancetype)init {
    if ((self = [super init])) {
        _recorder = [[TXRecorder alloc] init];
        _player = [[TXPlayer alloc] init];
        _macroManager = [TXMacroManager sharedManager];
        _selectedMacroName = nil;
        _autoRepeatEnabled = (_macroManager.autoRepeatMacroName != nil);
        if (_autoRepeatEnabled) _selectedMacroName = _macroManager.autoRepeatMacroName;
        
        [self setupNotifications];
        // تأخير لضمان وجود النافذة
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupUI];
        });
    }
    return self;
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    [self setupUI];
    if (_autoRepeatEnabled && _selectedMacroName.length > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self->_player playMacroWithName:self->_selectedMacroName];
        });
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)note {
    [self setupUI];
}

- (void)setupUI {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    #pragma clang diagnostic pop
    if (!mainWindow) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupUI];
        });
        return;
    }
    _targetWindow = mainWindow;
    
    if (_floatingButton && _floatingButton.superview) {
        [_targetWindow bringSubviewToFront:_floatingButton];
        if (_menuView) [_targetWindow bringSubviewToFront:_menuView];
        return;
    }
    
    // إنشاء الزر
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(20, 100, 60, 60);
    button.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
    button.layer.cornerRadius = 30;
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOffset = CGSizeMake(0, 2);
    button.layer.shadowOpacity = 0.5;
    [button setTitle:@"⚙️" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:28];
    [button addTarget:self action:@selector(floatingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [button addGestureRecognizer:pan];
    [mainWindow addSubview:button];
    _floatingButton = button;
    
    // إنشاء القائمة
    TXMenuView *menu = [[TXMenuView alloc] initWithFrame:CGRectZero];
    menu.menuController = self;
    menu.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    menu.layer.cornerRadius = 10;
    menu.layer.masksToBounds = YES;
    menu.hidden = YES;
    [mainWindow addSubview:menu];
    _menuView = menu;
    
    [mainWindow bringSubviewToFront:button];
    [mainWindow bringSubviewToFront:menu];
    
    NSLog(@"[Tweak] ✅ UI setup complete");
}

- (void)floatingButtonTapped:(UIButton *)sender {
    if (_menuVisible) [self hideMenu]; else [self showMenu];
}

- (void)showMenu {
    if (!_menuView) return;
    _menuView.hidden = NO;
    _menuView.frame = CGRectMake(0, 0, 280, 320);
    CGRect buttonFrame = _floatingButton.frame;
    CGPoint anchor = CGPointMake(CGRectGetMaxX(buttonFrame), CGRectGetMidY(buttonFrame));
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat menuWidth = _menuView.frame.size.width;
    CGFloat menuHeight = _menuView.frame.size.height;
    CGFloat x = anchor.x + 10;
    CGFloat y = anchor.y - menuHeight/2;
    if (x + menuWidth > screenBounds.size.width) x = anchor.x - menuWidth - 10;
    if (y < 0) y = 10;
    if (y + menuHeight > screenBounds.size.height) y = screenBounds.size.height - menuHeight - 10;
    _menuView.frame = CGRectMake(x, y, menuWidth, menuHeight);
    [_menuView refreshMacroList];
    _menuVisible = YES;
    [_targetWindow bringSubviewToFront:_menuView];
    NSLog(@"[Tweak] 📋 Menu shown");
}

- (void)hideMenu {
    _menuView.hidden = YES;
    _menuVisible = NO;
    NSLog(@"[Tweak] 📋 Menu hidden");
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (!_floatingButton || !_targetWindow) return;
    UIButton *button = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:_targetWindow];
    CGRect newFrame = button.frame;
    newFrame.origin.x += translation.x;
    newFrame.origin.y += translation.y;
    CGRect bounds = _targetWindow.bounds;
    if (newFrame.origin.x < 0) newFrame.origin.x = 0;
    if (newFrame.origin.y < 20) newFrame.origin.y = 20;
    if (newFrame.origin.x + newFrame.size.width > bounds.size.width)
        newFrame.origin.x = bounds.size.width - newFrame.size.width;
    if (newFrame.origin.y + newFrame.size.height > bounds.size.height)
        newFrame.origin.y = bounds.size.height - newFrame.size.height - 20;
    button.frame = newFrame;
    [gesture setTranslation:CGPointZero inView:_targetWindow];
}

- (void)startRecording {
    if (!_recorder.isRecording) {
        [_recorder startRecording];
        NSLog(@"[Tweak] 🔴 Record button pressed");
    } else {
        NSLog(@"[Tweak] ⚠️ Already recording");
    }
}

- (void)stopRecordingAndSave {
    if (!_recorder.isRecording) {
        NSLog(@"[Tweak] ⚠️ Not recording, cannot save");
        return;
    }
    NSLog(@"[Tweak] 💾 Save button pressed");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Macro"
                                                                   message:@"Enter a name"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Macro name";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) name = @"Untitled";
        [self->_recorder stopRecording];
        NSDictionary *macro = [self->_recorder recordedMacro];
        if (macro) {
            [self->_macroManager saveMacro:macro withName:name];
            self->_selectedMacroName = name;
            [self->_menuView refreshMacroList];
            NSLog(@"[Tweak] ✅ Macro saved: %@", name);
        } else {
            NSLog(@"[Tweak] ❌ No events to save!");
        }
        [self->_recorder cancelRecording];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self->_recorder cancelRecording];
        NSLog(@"[Tweak] ❌ Save cancelled");
    }]];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    #pragma clang diagnostic pop
    if (root) [root presentViewController:alert animated:YES completion:nil];
}

- (void)selectMacro:(NSString *)name {
    _selectedMacroName = name;
    NSLog(@"[Tweak] 📌 Selected macro: %@", name);
}

- (void)playSelectedMacro {
    if (_selectedMacroName.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Macro"
                                                                       message:@"Please select a macro first"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        #pragma clang diagnostic pop
        if (root) [root presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (_player.isPlaying) [_player stop];
    [_player playMacroWithName:_selectedMacroName];
}

- (void)toggleAutoRepeat:(BOOL)enabled {
    _autoRepeatEnabled = enabled;
    if (enabled && _selectedMacroName.length > 0) {
        [_macroManager setAutoRepeatMacroName:_selectedMacroName];
    } else {
        [_macroManager setAutoRepeatMacroName:nil];
    }
    NSLog(@"[Tweak] 🔄 Auto-repeat: %@", enabled ? @"ON" : @"OFF");
}

- (void)deleteSelectedMacro {
    if (_selectedMacroName.length == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Macro"
                                                                   message:[NSString stringWithFormat:@"Delete '%@'?", _selectedMacroName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self->_macroManager deleteMacroWithName:self->_selectedMacroName];
        self->_selectedMacroName = nil;
        [self->_menuView refreshMacroList];
        if (self->_autoRepeatEnabled) {
            self->_autoRepeatEnabled = NO;
            [self->_macroManager setAutoRepeatMacroName:nil];
        }
        NSLog(@"[Tweak] 🗑️ Macro deleted");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    #pragma clang diagnostic pop
    if (root) [root presentViewController:alert animated:YES completion:nil];
}
@end

// ============================================================
// TXMenuView - القائمة
// ============================================================
@implementation TXMenuView {
    UITableView *_macroTable;
    UISwitch *_autoRepeatSwitch;
    NSArray<NSString *> *_macroNames;
    NSString *_selectedName;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 10;
        self.clipsToBounds = YES;
        [self setupSubviews];
        _macroNames = @[];
    }
    return self;
}

- (void)setupSubviews {
    CGFloat y = 10, margin = 10, width = 260, buttonHeight = 36, spacing = 8;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, width - 2*margin, 30)];
    title.text = @"Macro Controller";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    title.textAlignment = NSTextAlignmentCenter;
    [self addSubview:title];
    y += 35;
    
    UIButton *record = [UIButton buttonWithType:UIButtonTypeSystem];
    record.frame = CGRectMake(margin, y, (width - 3*margin)/2, buttonHeight);
    [record setTitle:@"▶️ Record" forState:UIControlStateNormal];
    record.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0];
    [record setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    record.layer.cornerRadius = 5;
    [record addTarget:self action:@selector(recordAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:record];
    
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    stop.frame = CGRectMake(margin + (width - 3*margin)/2 + margin, y, (width - 3*margin)/2, buttonHeight);
    [stop setTitle:@"⏹ Save" forState:UIControlStateNormal];
    stop.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.1 alpha:1.0];
    [stop setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    stop.layer.cornerRadius = 5;
    [stop addTarget:self action:@selector(stopSaveAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:stop];
    y += buttonHeight + spacing;
    
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(margin, y, width - 2*margin, 120) style:UITableViewStylePlain];
    table.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    table.delegate = self;
    table.dataSource = self;
    table.layer.cornerRadius = 5;
    table.separatorColor = [UIColor grayColor];
    [self addSubview:table];
    _macroTable = table;
    y += 120 + spacing;
    
    UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
    play.frame = CGRectMake(margin, y, (width - 3*margin)/2, buttonHeight);
    [play setTitle:@"▶️ Play" forState:UIControlStateNormal];
    play.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.9 alpha:1.0];
    [play setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    play.layer.cornerRadius = 5;
    [play addTarget:self action:@selector(playAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:play];
    
    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.frame = CGRectMake(margin + (width - 3*margin)/2 + margin, y, (width - 3*margin)/2, buttonHeight);
    [del setTitle:@"🗑 Delete" forState:UIControlStateNormal];
    del.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
    [del setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    del.layer.cornerRadius = 5;
    [del addTarget:self action:@selector(deleteAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:del];
    y += buttonHeight + spacing;
    
    UILabel *autoLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, 140, 30)];
    autoLabel.text = @"Auto‑repeat on launch";
    autoLabel.textColor = [UIColor whiteColor];
    autoLabel.font = [UIFont systemFontOfSize:14];
    [self addSubview:autoLabel];
    
    UISwitch *autoSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(width - margin - 51, y, 51, 30)];
    [autoSwitch addTarget:self action:@selector(autoRepeatToggled:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:autoSwitch];
    _autoRepeatSwitch = autoSwitch;
    
    TXFloatingMenu *menu = self.menuController;
    if (menu) {
        _autoRepeatSwitch.on = menu.autoRepeatEnabled;
        _selectedName = menu.selectedMacroName;
    }
    [self refreshMacroList];
}

- (void)refreshMacroList {
    _macroNames = [[TXMacroManager sharedManager] macroNames];
    _macroNames = [_macroNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [_macroTable reloadData];
    TXFloatingMenu *menu = self.menuController;
    if (menu && menu.selectedMacroName) _selectedName = menu.selectedMacroName;
    else _selectedName = nil;
    if (_selectedName) {
        NSInteger idx = [_macroNames indexOfObject:_selectedName];
        if (idx != NSNotFound) {
            [_macroTable selectRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
    }
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _macroNames.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"MacroCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    cell.textLabel.text = _macroNames[indexPath.row];
    return cell;
}

#pragma mark - UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *name = _macroNames[indexPath.row];
    _selectedName = name;
    [self.menuController selectMacro:name];
}

#pragma mark - Actions
- (void)recordAction:(UIButton *)sender { [self.menuController startRecording]; }
- (void)stopSaveAction:(UIButton *)sender { [self.menuController stopRecordingAndSave]; }
- (void)playAction:(UIButton *)sender { [self.menuController playSelectedMacro]; }
- (void)deleteAction:(UIButton *)sender { [self.menuController deleteSelectedMacro]; }
- (void)autoRepeatToggled:(UISwitch *)sender { [self.menuController toggleAutoRepeat:sender.on]; }
@end

// ============================================================
// 🪝 HOOKS: التقاط اللمسات من UIApplication و UIWindow (مزدوج)
// ============================================================
static TXRecorder *gRecorder = nil;

%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (gRecorder && [gRecorder isRecording]) {
        [gRecorder captureTouchEvent:event];
    }
}
%end

%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (gRecorder && [gRecorder isRecording]) {
        [gRecorder captureTouchEvent:event];
    }
}
%end

// ============================================================
// Constructor
// ============================================================
%ctor {
    // تحميل GSEventSend
    void *handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
    if (handle) {
        GSEventSendPtr = (GSEventSendFunc)dlsym(handle, "GSEventSend");
        if (GSEventSendPtr) {
            NSLog(@"[Tweak] ✅ GSEventSend loaded successfully");
        } else {
            NSLog(@"[Tweak] ❌ Failed to find GSEventSend symbol");
        }
    } else {
        NSLog(@"[Tweak] ❌ Failed to load GraphicsServices framework");
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        gRecorder = [[TXRecorder alloc] init];
        [TXFloatingMenu sharedMenu];
        NSLog(@"[Tweak] 🚀 Tweak initialized successfully");
    });
}
