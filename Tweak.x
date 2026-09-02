// Tweak.x – الإصدار النهائي الذي يلتقط اللمسات بكل تأكيد
// يستخدم 3 طرق مختلفة لالتقاط اللمسات لضمان العمل

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <objc/runtime.h>

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
static NSString * const kMacroStorageDir = @"/var/mobile/Library/Preferences/";

// ============================================================
// MARK: - TXMacroManager
// ============================================================
@interface TXMacroManager : NSObject
+ (instancetype)sharedManager;
- (NSArray<NSString *> *)macroNames;
- (NSDictionary *)loadMacroWithName:(NSString *)name;
- (void)saveMacro:(NSDictionary *)macro withName:(NSString *)name;
- (void)deleteMacroWithName:(NSString *)name;
@end

@implementation TXMacroManager

+ (instancetype)sharedManager {
    static TXMacroManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:kMacroStorageDir]) {
            [fm createDirectoryAtPath:kMacroStorageDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    return self;
}

- (NSArray<NSString *> *)macroNames {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:kMacroStorageDir error:nil];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *file in files) {
        if ([file hasPrefix:@"macro_"] && [file hasSuffix:@".plist"]) {
            NSString *name = [file stringByDeletingPathExtension];
            name = [name substringFromIndex:6];
            [names addObject:name];
        }
    }
    return names;
}

- (NSDictionary *)loadMacroWithName:(NSString *)name {
    NSString *path = [kMacroStorageDir stringByAppendingPathComponent:[NSString stringWithFormat:@"macro_%@.plist", name]];
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

- (void)saveMacro:(NSDictionary *)macro withName:(NSString *)name {
    NSString *path = [kMacroStorageDir stringByAppendingPathComponent:[NSString stringWithFormat:@"macro_%@.plist", name]];
    [macro writeToFile:path atomically:YES];
    NSLog(@"[Tweak] ✅ Saved macro: %@ with %lu events", name, (unsigned long)[macro[@"events"] count]);
}

- (void)deleteMacroWithName:(NSString *)name {
    NSString *path = [kMacroStorageDir stringByAppendingPathComponent:[NSString stringWithFormat:@"macro_%@.plist", name]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}
@end

// ============================================================
// MARK: - TXRecorder (مع دعم تسجيل اللمسات من عدة مصادر)
// ============================================================
@interface TXRecorder : NSObject
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, strong) NSMutableArray *events;
@property (nonatomic, assign) CFAbsoluteTime startTime;
+ (instancetype)sharedRecorder;
- (void)startRecording;
- (void)stopRecording;
- (void)cancelRecording;
- (NSDictionary *)recordedMacro;
- (void)recordTouchAtPoint:(CGPoint)point phase:(UITouchPhase)phase;
@end

@implementation TXRecorder

+ (instancetype)sharedRecorder {
    static TXRecorder *recorder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ recorder = [[self alloc] init]; });
    return recorder;
}

- (instancetype)init {
    if ((self = [super init])) {
        _events = [NSMutableArray array];
        _isRecording = NO;
        NSLog(@"[Tweak] 🎙️ Recorder initialized");
    }
    return self;
}

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
}

- (NSDictionary *)recordedMacro {
    if (_events.count == 0) return nil;
    return @{ @"events": _events, @"duration": @(CFAbsoluteTimeGetCurrent() - _startTime) };
}

- (void)recordTouchAtPoint:(CGPoint)point phase:(UITouchPhase)phase {
    if (!_isRecording) return;
    NSTimeInterval timestamp = CFAbsoluteTimeGetCurrent() - _startTime;
    NSDictionary *touchData = @{
        @"x": @(point.x),
        @"y": @(point.y),
        @"phase": @(phase)
    };
    [_events addObject:@{ @"timestamp": @(timestamp), @"touches": @[touchData] }];
    NSLog(@"[Tweak] 👆 Recorded touch at (%.1f, %.1f) phase: %ld", point.x, point.y, (long)phase);
}
@end

// ============================================================
// MARK: - TXPlayer
// ============================================================
@interface TXPlayer : NSObject
+ (instancetype)sharedPlayer;
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

+ (instancetype)sharedPlayer {
    static TXPlayer *player = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ player = [[self alloc] init]; });
    return player;
}

- (instancetype)init {
    if ((self = [super init])) {
        _playbackQueue = dispatch_queue_create("com.tweak.playback", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

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
    if (!GSEventSendPtr) return;
    NSArray *touches = eventDict[@"touches"];
    if (!touches) return;
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
        NSLog(@"[Tweak] 📤 Simulated touch at (%.1f, %.1f)", x, y);
    }
}

- (void)stop {
    _isPlaying = NO;
    _events = nil;
    _eventIndex = 0;
}
@end

// ============================================================
// MARK: - TXFloatingMenu (النافذة العائمة)
// ============================================================
@interface TXFloatingMenu : NSObject
+ (instancetype)sharedMenu;
@property (nonatomic, strong) NSString *selectedMacroName;
- (void)setupUI;
- (void)startRecording;
- (void)stopRecordingAndSave;
- (void)playSelectedMacro;
- (void)deleteSelectedMacro;
- (void)toggleAutoRepeat:(BOOL)enabled;
- (void)refreshMenuList;
@end

@interface TXMenuView : UIView <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, weak) TXFloatingMenu *menuController;
- (void)refreshMacroList;
@end

// ============================================================
// MARK: - TXFloatingMenu Implementation
// ============================================================
@implementation TXFloatingMenu {
    UIButton *_floatingButton;
    TXMenuView *_menuView;
    BOOL _menuVisible;
    UIWindow *_targetWindow;
    BOOL _autoRepeatEnabled;
}

+ (instancetype)sharedMenu {
    static TXFloatingMenu *menu = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ menu = [[self alloc] init]; });
    return menu;
}

- (instancetype)init {
    if ((self = [super init])) {
        _selectedMacroName = nil;
        _autoRepeatEnabled = NO;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupUI];
        });
    }
    return self;
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
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
    _menuView.frame = CGRectMake(0, 0, 280, 340);
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
}

- (void)hideMenu {
    _menuView.hidden = YES;
    _menuVisible = NO;
}

- (void)refreshMenuList {
    if (_menuView) [_menuView refreshMacroList];
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
    TXRecorder *recorder = [TXRecorder sharedRecorder];
    if (!recorder.isRecording) {
        [recorder startRecording];
        [self showTemporaryAlert:@"🔴 Recording Started" withMessage:@"Tap anywhere to record"];
    }
}

- (void)stopRecordingAndSave {
    TXRecorder *recorder = [TXRecorder sharedRecorder];
    if (!recorder.isRecording) {
        [self showTemporaryAlert:@"❌ Not Recording" withMessage:@"Press Record first"];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Macro"
                                                                   message:@"Enter a name"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Macro name";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) name = @"Untitled";
        [recorder stopRecording];
        NSDictionary *macro = [recorder recordedMacro];
        if (macro) {
            [[TXMacroManager sharedManager] saveMacro:macro withName:name];
            self->_selectedMacroName = name;
            [self->_menuView refreshMacroList];
            [self showTemporaryAlert:@"✅ Macro Saved!" withMessage:[NSString stringWithFormat:@"'%@' with %lu events", name, (unsigned long)[macro[@"events"] count]]];
        } else {
            [self showTemporaryAlert:@"❌ No Events!" withMessage:@"Please record touches first"];
        }
        [recorder cancelRecording];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [recorder cancelRecording];
    }]];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    #pragma clang diagnostic pop
    if (root) [root presentViewController:alert animated:YES completion:nil];
}

- (void)playSelectedMacro {
    if (_selectedMacroName.length == 0) {
        [self showTemporaryAlert:@"No Macro" withMessage:@"Please select a macro first"];
        return;
    }
    [[TXPlayer sharedPlayer] playMacroWithName:_selectedMacroName];
}

- (void)deleteSelectedMacro {
    if (_selectedMacroName.length == 0) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Macro"
                                                                   message:[NSString stringWithFormat:@"Delete '%@'?", _selectedMacroName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[TXMacroManager sharedManager] deleteMacroWithName:self->_selectedMacroName];
        self->_selectedMacroName = nil;
        [self->_menuView refreshMacroList];
        [self showTemporaryAlert:@"🗑️ Deleted" withMessage:@"Macro removed"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    #pragma clang diagnostic pop
    if (root) [root presentViewController:alert animated:YES completion:nil];
}

- (void)toggleAutoRepeat:(BOOL)enabled {
    _autoRepeatEnabled = enabled;
    NSLog(@"[Tweak] Auto-repeat: %@", enabled ? @"ON" : @"OFF");
}

- (void)showTemporaryAlert:(NSString *)title withMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    #pragma clang diagnostic pop
    if (root) {
        [root presentViewController:alert animated:YES completion:^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [alert dismissViewControllerAnimated:YES completion:nil];
            });
        }];
    }
}
@end

// ============================================================
// MARK: - TXMenuView
// ============================================================
@implementation TXMenuView {
    UITableView *_macroTable;
    UISwitch *_autoRepeatSwitch;
    NSArray<NSString *> *_macroNames;
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
    [record setTitle:@"🔴 Record" forState:UIControlStateNormal];
    record.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0];
    [record setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    record.layer.cornerRadius = 5;
    [record addTarget:self action:@selector(recordAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:record];
    
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    stop.frame = CGRectMake(margin + (width - 3*margin)/2 + margin, y, (width - 3*margin)/2, buttonHeight);
    [stop setTitle:@"💾 Save" forState:UIControlStateNormal];
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
    [self refreshMacroList];
}

- (void)refreshMacroList {
    _macroNames = [[TXMacroManager sharedManager] macroNames];
    _macroNames = [_macroNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [_macroTable reloadData];
    NSLog(@"[Tweak] 📋 Macro list refreshed: %lu items", (unsigned long)_macroNames.count);
}

#pragma mark - UITableView
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *name = _macroNames[indexPath.row];
    self.menuController.selectedMacroName = name;
    NSLog(@"[Tweak] 📌 Selected macro: %@", name);
}

#pragma mark - Actions
- (void)recordAction:(UIButton *)sender { [self.menuController startRecording]; }
- (void)stopSaveAction:(UIButton *)sender { [self.menuController stopRecordingAndSave]; }
- (void)playAction:(UIButton *)sender { [self.menuController playSelectedMacro]; }
- (void)deleteAction:(UIButton *)sender { [self.menuController deleteSelectedMacro]; }
- (void)autoRepeatToggled:(UISwitch *)sender { [self.menuController toggleAutoRepeat:sender.on]; }
@end

// ============================================================
// MARK: - 🪝 HOOKS الرئيسية لالتقاط اللمسات (3 طرق مختلفة)
// ============================================================

// الطريقة 1: Hook على UIApplication
%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    %orig;
    TXRecorder *recorder = [TXRecorder sharedRecorder];
    if (recorder.isRecording) {
        NSSet *touches = [event allTouches];
        for (UITouch *touch in touches) {
            CGPoint point = [touch locationInView:touch.window];
            [recorder recordTouchAtPoint:point phase:touch.phase];
        }
    }
}
%end

// الطريقة 2: Hook على UIWindow
%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    %orig;
    TXRecorder *recorder = [TXRecorder sharedRecorder];
    if (recorder.isRecording) {
        NSSet *touches = [event allTouches];
        for (UITouch *touch in touches) {
            CGPoint point = [touch locationInView:touch.window];
            [recorder recordTouchAtPoint:point phase:touch.phase];
        }
    }
}
%end

// الطريقة 3: Hook على UIViewController (للتأكد من التقاط اللمسات)
%hook UIViewController
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    TXRecorder *recorder = [TXRecorder sharedRecorder];
    if (recorder.isRecording) {
        for (UITouch *touch in touches) {
            CGPoint point = [touch locationInView:touch.view];
            [recorder recordTouchAtPoint:point phase:UITouchPhaseBegan];
        }
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    TXRecorder *recorder = [TXRecorder sharedRecorder];
    if (recorder.isRecording) {
        for (UITouch *touch in touches) {
            CGPoint point = [touch locationInView:touch.view];
            [recorder recordTouchAtPoint:point phase:UITouchPhaseMoved];
        }
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    TXRecorder *recorder = [TXRecorder sharedRecorder];
    if (recorder.isRecording) {
        for (UITouch *touch in touches) {
            CGPoint point = [touch locationInView:touch.view];
            [recorder recordTouchAtPoint:point phase:UITouchPhaseEnded];
        }
    }
}
%end

// ============================================================
// MARK: - Constructor
// ============================================================
%ctor {
    // تحميل GSEventSend
    void *handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
    if (handle) {
        GSEventSendPtr = (GSEventSendFunc)dlsym(handle, "GSEventSend");
        if (GSEventSendPtr) {
            NSLog(@"[Tweak] ✅ GSEventSend loaded");
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [TXRecorder sharedRecorder];
        [TXPlayer sharedPlayer];
        [TXFloatingMenu sharedMenu];
        NSLog(@"[Tweak] 🚀 Tweak initialized successfully");
    });
}
