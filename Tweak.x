// Tweak.x
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
// مسار التخزين
// ============================================================
static NSString * const kMacroStorageDir = @"/var/mobile/Library/Preferences/com.tweak.macros/";
static NSString * const kAutoRepeatKey = @"AutoRepeatMacroName";

// ============================================================
// TXMacroManager (نفس السابق)
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
        if (![fm fileExistsAtPath:dir])
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
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
        if ([file hasSuffix:@".plist"] && ![file isEqualToString:@"autoRepeat.plist"])
            [names addObject:[file stringByDeletingPathExtension]];
    }
    return names;
}
- (NSDictionary *)loadMacroWithName:(NSString *)name {
    NSString *path = [[self persistentDirectory] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
    return [NSDictionary dictionaryWithContentsOfFile:path];
}
- (void)saveMacro:(NSDictionary *)macro withName:(NSString *)name {
    NSString *path = [[self persistentDirectory] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
    [macro writeToFile:path atomically:YES];
}
- (void)deleteMacroWithName:(NSString *)name {
    NSString *path = [[self persistentDirectory] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}
- (NSString *)autoRepeatMacroName { return _autoRepeatPreference[kAutoRepeatKey]; }
- (void)setAutoRepeatMacroName:(NSString *)name {
    if (name) _autoRepeatPreference[kAutoRepeatKey] = name;
    else [_autoRepeatPreference removeObjectForKey:kAutoRepeatKey];
    NSString *prefPath = [[self persistentDirectory] stringByAppendingPathComponent:@"autoRepeat.plist"];
    [_autoRepeatPreference writeToFile:prefPath atomically:YES];
}
@end

// ============================================================
// TXRecorder (نفس السابق)
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
    if ((self = [super init])) { _events = [NSMutableArray array]; _isRecording = NO; }
    return self;
}
- (BOOL)isRecording { return _isRecording; }
- (void)startRecording {
    _isRecording = YES;
    [_events removeAllObjects];
    _startTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"[Tweak] Recording started");
}
- (void)stopRecording { _isRecording = NO; NSLog(@"[Tweak] Recording stopped"); }
- (void)cancelRecording { _isRecording = NO; [_events removeAllObjects]; }
- (NSDictionary *)recordedMacro {
    if (_events.count == 0) return nil;
    return @{ @"events": _events, @"duration": @(CFAbsoluteTimeGetCurrent() - _startTime) };
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
    NSLog(@"[Tweak] Captured touch at (%.1f, %.1f)", [touchData[0][@"x"] floatValue], [touchData[0][@"y"] floatValue]);
}
@end

// ============================================================
// TXPlayer (نفس السابق مع إضافة فحص GSEventSend)
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
    }
    return self;
}
- (BOOL)isPlaying { return _isPlaying; }
- (void)playMacro:(NSDictionary *)macro {
    [self stop];
    NSArray *events = macro[@"events"];
    if (!events.count) return;
    _events = events;
    _eventIndex = 0;
    _isPlaying = YES;
    _playStartTime = CFAbsoluteTimeGetCurrent();
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
        NSLog(@"[Tweak] GSEventSend not loaded!");
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
    }
}
- (void)stop { _isPlaying = NO; _events = nil; _eventIndex = 0; }
@end

// ============================================================
// TXFloatingMenu و TXMenuView (مع إضافة HitTest)
// ============================================================
// نضيف UIView مخصصة لتمرير اللمس
@interface TouchPassThroughView : UIView
@property (nonatomic, weak) UIButton *floatingButton;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation TouchPassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // التحقق إذا كانت النقطة فوق الزر أو القائمة
    if (_floatingButton && !_floatingButton.hidden && 
        CGRectContainsPoint(_floatingButton.frame, point)) {
        return _floatingButton;
    }
    if (_menuView && !_menuView.hidden && 
        CGRectContainsPoint(_menuView.frame, point)) {
        // نجد الـ subview داخل القائمة التي تريد اللمس (مثل الأزرار والجدول)
        for (UIView *subview in _menuView.subviews) {
            CGPoint subPoint = [self convertPoint:point toView:subview];
            if ([subview pointInside:subPoint withEvent:event]) {
                return subview;
            }
        }
        return _menuView; // إذا كانت النقطة فوق القائمة لكن ليست على عنصر محدد، نمررها للقائمة نفسها
    }
    // وإلا نمرر اللمس للتطبيق الأصلي
    return nil;
}
@end

// ... (باقي الكود لـ TXFloatingMenu و TXMenuView مع التعديلات)
// الآن نضيف الـ root view المخصص بدلاً من الـ UIViewController العادي

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
@end

@interface TXMenuView : UIView <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, weak) TXFloatingMenu *menuController;
- (void)refreshMacroList;
@end

@implementation TXFloatingMenu {
    UIWindow *_floatingWindow;
    UIButton *_floatingButton;
    TXMenuView *_menuView;
    BOOL _menuVisible;
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
        [self setupFloatingWindow];
        [self setupNotifications];
    }
    return self;
}
- (void)setupFloatingWindow {
    UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.windowLevel = UIWindowLevelAlert + 1;
    window.backgroundColor = [UIColor clearColor];
    window.userInteractionEnabled = YES;
    window.hidden = NO;
    
    // استخدام الـ View المخصص بدلاً من UIViewController
    TouchPassThroughView *rootView = [[TouchPassThroughView alloc] initWithFrame:window.bounds];
    rootView.backgroundColor = [UIColor clearColor];
    rootView.userInteractionEnabled = YES;
    window.rootViewController = [[UIViewController alloc] init];
    window.rootViewController.view = rootView;
    
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
    [rootView addSubview:button];
    _floatingButton = button;
    rootView.floatingButton = button; // ربطه للـ hitTest
    
    TXMenuView *menu = [[TXMenuView alloc] initWithFrame:CGRectZero];
    menu.menuController = self;
    menu.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    menu.layer.cornerRadius = 10;
    menu.layer.masksToBounds = YES;
    menu.hidden = YES;
    [rootView addSubview:menu];
    _menuView = menu;
    rootView.menuView = menu;
    
    _floatingWindow = window;
}
// ... باقي التوابع (applicationDidBecomeActive, show/hide menu, handlePan, actions) كما هي دون تغيير
// تأكد من أن جميع التوابع موجودة كما في الكود السابق، لكنني سأضعها مختصرة للاختصار.

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)applicationDidBecomeActive:(NSNotification *)note {
    if (_autoRepeatEnabled && _selectedMacroName.length > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self->_player playMacroWithName:self->_selectedMacroName];
        });
    }
}
- (void)floatingButtonTapped:(UIButton *)sender {
    if (_menuVisible) [self hideMenu]; else [self showMenu];
}
- (void)showMenu {
    // ... كما في السابق
}
- (void)hideMenu { _menuView.hidden = YES; _menuVisible = NO; }
- (void)handlePan:(UIPanGestureRecognizer *)gesture { /* كما في السابق */ }
- (void)startRecording { if (!_recorder.isRecording) [_recorder startRecording]; }
- (void)stopRecordingAndSave {
    if (!_recorder.isRecording) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Macro" message:@"Enter a name" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.placeholder = @"Macro name"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) name = @"Untitled";
        [self->_recorder stopRecording];
        NSDictionary *macro = [self->_recorder recordedMacro];
        if (macro) {
            [self->_macroManager saveMacro:macro withName:name];
            self->_selectedMacroName = name;
            [self->_menuView refreshMacroList];
        }
        [self->_recorder cancelRecording];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self->_recorder cancelRecording];
    }]];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    #pragma clang diagnostic pop
    [root presentViewController:alert animated:YES completion:nil];
}
- (void)selectMacro:(NSString *)name { _selectedMacroName = name; }
- (void)playSelectedMacro {
    if (_selectedMacroName.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Macro" message:@"Please select a macro first" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        #pragma clang diagnostic pop
        [root presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (_player.isPlaying) [_player stop];
    [_player playMacroWithName:_selectedMacroName];
}
- (void)toggleAutoRepeat:(BOOL)enabled {
    _autoRepeatEnabled = enabled;
    if (enabled && _selectedMacroName.length > 0) [_macroManager setAutoRepeatMacroName:_selectedMacroName];
    else [_macroManager setAutoRepeatMacroName:nil];
}
- (void)deleteSelectedMacro {
    if (_selectedMacroName.length == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Macro" message:[NSString stringWithFormat:@"Delete '%@'?", _selectedMacroName] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self->_macroManager deleteMacroWithName:self->_selectedMacroName];
        self->_selectedMacroName = nil;
        [self->_menuView refreshMacroList];
        if (self->_autoRepeatEnabled) {
            self->_autoRepeatEnabled = NO;
            [self->_macroManager setAutoRepeatMacroName:nil];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    #pragma clang diagnostic pop
    [root presentViewController:alert animated:YES completion:nil];
}
@end

// ============================================================
// TXMenuView (كما هو دون تغيير)
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
    // ... كما في الكود السابق (لم يتغير)
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
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _macroNames.count; }
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
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *name = _macroNames[indexPath.row];
    _selectedName = name;
    [self.menuController selectMacro:name];
}
- (void)recordAction:(UIButton *)sender { [self.menuController startRecording]; }
- (void)stopSaveAction:(UIButton *)sender { [self.menuController stopRecordingAndSave]; }
- (void)playAction:(UIButton *)sender { [self.menuController playSelectedMacro]; }
- (void)deleteAction:(UIButton *)sender { [self.menuController deleteSelectedMacro]; }
- (void)autoRepeatToggled:(UISwitch *)sender { [self.menuController toggleAutoRepeat:sender.on]; }
@end

// ============================================================
// Hook و Constructor
// ============================================================
static TXRecorder *gRecorder = nil;

%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (gRecorder && [gRecorder isRecording]) [gRecorder captureTouchEvent:event];
}
%end

%ctor {
    void *handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
    if (handle) GSEventSendPtr = (GSEventSendFunc)dlsym(handle, "GSEventSend");
    if (!GSEventSendPtr) NSLog(@"[Tweak] GSEventSend not loaded!");
    else NSLog(@"[Tweak] GSEventSend loaded successfully.");
    dispatch_async(dispatch_get_main_queue(), ^{
        gRecorder = [[TXRecorder alloc] init];
        [TXFloatingMenu sharedMenu];
    });
}
