// Tweak.x
// Advanced Touch Recorder & Macro Player Tweak
// Persistent storage: /var/mobile/Library/Preferences/com.tweak.macros/

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <GraphicsServices/GraphicsServices.h>   // for GSEvent simulation

// ============================================================================
// Private GSEvent structures
// ============================================================================
typedef enum {
    kGSEventTypeTouch = 0x0011,
} GSEventType;

typedef enum {
    kGSEventSubtypeTouch = 0x0000,
} GSEventSubtype;

typedef enum {
    kGSEventTouchPhaseBegan    = 0,
    kGSEventTouchPhaseMoved    = 1,
    kGSEventTouchPhaseEnded    = 2,
    kGSEventTouchPhaseCancelled= 3,
} GSEventTouchPhase;

typedef struct {
    uint8_t        type;
    uint8_t        subtype;
    int16_t        windowNum;
    int16_t        windowNum2;
    CGPoint        point;
    uint32_t       timestamp;
    uint8_t        phase;
    uint8_t        flags;
    uint8_t        pathIndex;
    uint8_t        pathIdentity;
} GSEventRecord;

extern void GSEventSend(GSEventRecord *event);

// ============================================================================
// Persistent Storage Path
// ============================================================================
static NSString * const kMacroStorageDir = @"/var/mobile/Library/Preferences/com.tweak.macros/";
static NSString * const kAutoRepeatKey = @"AutoRepeatMacroName";

// ============================================================================
// TXMacroManager – persistence
// ============================================================================
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
    dispatch_once(&onceToken, ^{
        manager = [[TXMacroManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [self persistentDirectory];
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *prefPath = [dir stringByAppendingPathComponent:@"autoRepeat.plist"];
        if ([fm fileExistsAtPath:prefPath]) {
            _autoRepeatPreference = [NSMutableDictionary dictionaryWithContentsOfFile:prefPath];
        }
        if (!_autoRepeatPreference) {
            _autoRepeatPreference = [NSMutableDictionary dictionary];
        }
    }
    return self;
}

- (NSString *)persistentDirectory {
    return kMacroStorageDir;
}

- (NSArray<NSString *> *)macroNames {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [self persistentDirectory];
    NSError *error = nil;
    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:&error];
    if (error) return @[];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *file in files) {
        if ([file hasSuffix:@".plist"]) {
            NSString *name = [file stringByDeletingPathExtension];
            if (![name isEqualToString:@"autoRepeat"]) {
                [names addObject:name];
            }
        }
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

- (NSString *)autoRepeatMacroName {
    return _autoRepeatPreference[kAutoRepeatKey];
}

- (void)setAutoRepeatMacroName:(NSString *)name {
    if (name) {
        _autoRepeatPreference[kAutoRepeatKey] = name;
    } else {
        [_autoRepeatPreference removeObjectForKey:kAutoRepeatKey];
    }
    NSString *prefPath = [[self persistentDirectory] stringByAppendingPathComponent:@"autoRepeat.plist"];
    [_autoRepeatPreference writeToFile:prefPath atomically:YES];
}

@end

// ============================================================================
// TXRecorder – captures touch events
// ============================================================================
@interface TXRecorder : NSObject
@property (nonatomic, assign, readonly) BOOL isRecording;
@property (nonatomic, copy) NSString *currentRecordingName;
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
    }
    return self;
}

- (BOOL)isRecording {
    return _isRecording;
}

- (void)startRecording {
    _isRecording = YES;
    [_events removeAllObjects];
    _startTime = CFAbsoluteTimeGetCurrent();
    self.currentRecordingName = nil;
}

- (void)stopRecording {
    if (!_isRecording) return;
    _isRecording = NO;
}

- (void)cancelRecording {
    _isRecording = NO;
    [_events removeAllObjects];
}

- (NSDictionary *)recordedMacro {
    if (_events.count == 0) return nil;
    return @{ @"events": _events, @"duration": @(CFAbsoluteTimeGetCurrent() - _startTime) };
}

- (void)captureTouchEvent:(UIEvent *)event {
    if (!_isRecording) return;
    NSSet *touches = [event allTouches];
    if (!touches || touches.count == 0) return;
    
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSTimeInterval timestamp = now - _startTime;
    NSMutableArray *touchData = [NSMutableArray arrayWithCapacity:touches.count];
    for (UITouch *touch in touches) {
        CGPoint location = [touch locationInView:touch.window];
        NSDictionary *touchDict = @{
            @"x": @(location.x),
            @"y": @(location.y),
            @"phase": @(touch.phase)
        };
        [touchData addObject:touchDict];
    }
    NSDictionary *eventDict = @{
        @"timestamp": @(timestamp),
        @"touches": touchData
    };
    [_events addObject:eventDict];
}

@end

// ============================================================================
// TXPlayer – plays back macros
// ============================================================================
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

- (BOOL)isPlaying {
    return _isPlaying;
}

- (void)playMacro:(NSDictionary *)macro {
    [self stop];
    NSArray *events = macro[@"events"];
    if (!events || events.count == 0) return;
    
    _events = events;
    _eventIndex = 0;
    _isPlaying = YES;
    _playStartTime = CFAbsoluteTimeGetCurrent();
    [self scheduleNextEvent];
}

- (void)playMacroWithName:(NSString *)name {
    NSDictionary *macro = [[TXMacroManager sharedManager] loadMacroWithName:name];
    if (macro) {
        [self playMacro:macro];
    }
}

- (void)scheduleNextEvent {
    if (_eventIndex >= _events.count) {
        [self stop];
        return;
    }
    NSDictionary *event = _events[_eventIndex];
    NSTimeInterval relativeTime = [event[@"timestamp"] doubleValue];
    CFAbsoluteTime scheduledTime = _playStartTime + relativeTime;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSTimeInterval delay = scheduledTime - now;
    if (delay < 0) delay = 0;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), _playbackQueue, ^{
        if (!self->_isPlaying) return;
        [self executeEvent:event];
        self->_eventIndex++;
        [self scheduleNextEvent];
    });
}

- (void)executeEvent:(NSDictionary *)eventDict {
    NSArray *touches = eventDict[@"touches"];
    if (!touches) return;
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    for (NSDictionary *touchDict in touches) {
        CGFloat x = [touchDict[@"x"] floatValue];
        CGFloat y = [touchDict[@"y"] floatValue];
        UITouchPhase phase = (UITouchPhase)[touchDict[@"phase"] integerValue];
        
        GSEventRecord record = {0};
        record.type = kGSEventTypeTouch;
        record.subtype = kGSEventSubtypeTouch;
        record.windowNum = 0;
        record.windowNum2 = 0;
        record.point = CGPointMake(x, y);
        record.timestamp = (uint32_t)(CFAbsoluteTimeGetCurrent() * 1000);
        record.flags = 0;
        record.pathIndex = 0;
        record.pathIdentity = 0;
        
        switch (phase) {
            case UITouchPhaseBegan:    record.phase = kGSEventTouchPhaseBegan; break;
            case UITouchPhaseMoved:    record.phase = kGSEventTouchPhaseMoved; break;
            case UITouchPhaseEnded:    record.phase = kGSEventTouchPhaseEnded; break;
            default:                   record.phase = kGSEventTouchPhaseCancelled; break;
        }
        GSEventSend(&record);
    }
}

- (void)stop {
    _isPlaying = NO;
    _events = nil;
    _eventIndex = 0;
}

@end

// ============================================================================
// TXFloatingMenu – floating button + menu UI
// ============================================================================
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

// Menu view
@interface TXMenuView : UIView <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, weak) TXFloatingMenu *menuController;
- (void)refreshMacroList;
@end

// ============================================================================
// Implementation of TXFloatingMenu
// ============================================================================
@implementation TXFloatingMenu {
    UIWindow *_floatingWindow;
    UIButton *_floatingButton;
    TXMenuView *_menuView;
    BOOL _menuVisible;
}

+ (instancetype)sharedMenu {
    static TXFloatingMenu *menu = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        menu = [[TXFloatingMenu alloc] init];
    });
    return menu;
}

- (instancetype)init {
    if ((self = [super init])) {
        _recorder = [[TXRecorder alloc] init];
        _player = [[TXPlayer alloc] init];
        _macroManager = [TXMacroManager sharedManager];
        _selectedMacroName = nil;
        _autoRepeatEnabled = (_macroManager.autoRepeatMacroName != nil);
        if (_autoRepeatEnabled) {
            _selectedMacroName = _macroManager.autoRepeatMacroName;
        }
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
    window.rootViewController = [[UIViewController alloc] init];
    
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
    [window addSubview:button];
    _floatingButton = button;
    _floatingWindow = window;
    
    TXMenuView *menu = [[TXMenuView alloc] initWithFrame:CGRectZero];
    menu.menuController = self;
    menu.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    menu.layer.cornerRadius = 10;
    menu.layer.masksToBounds = YES;
    menu.hidden = YES;
    [window addSubview:menu];
    _menuView = menu;
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    if (_autoRepeatEnabled && _selectedMacroName.length > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self->_player playMacroWithName:self->_selectedMacroName];
        });
    }
}

- (void)floatingButtonTapped:(UIButton *)sender {
    if (_menuVisible) {
        [self hideMenu];
    } else {
        [self showMenu];
    }
}

- (void)showMenu {
    _menuView.hidden = NO;
    _menuView.frame = CGRectMake(0, 0, 280, 320);
    CGRect buttonFrame = _floatingButton.frame;
    CGPoint anchor = CGPointMake(CGRectGetMaxX(buttonFrame), CGRectGetMidY(buttonFrame));
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat menuWidth = _menuView.frame.size.width;
    CGFloat menuHeight = _menuView.frame.size.height;
    CGFloat x = anchor.x + 10;
    CGFloat y = anchor.y - menuHeight/2;
    if (x + menuWidth > screenBounds.size.width) {
        x = anchor.x - menuWidth - 10;
    }
    if (y < 0) y = 10;
    if (y + menuHeight > screenBounds.size.height) {
        y = screenBounds.size.height - menuHeight - 10;
    }
    _menuView.frame = CGRectMake(x, y, menuWidth, menuHeight);
    [_menuView refreshMacroList];
    _menuVisible = YES;
}

- (void)hideMenu {
    _menuView.hidden = YES;
    _menuVisible = NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIButton *button = (UIButton *)gesture.view;
    CGPoint translation = [gesture translationInView:_floatingWindow];
    CGRect newFrame = button.frame;
    newFrame.origin.x += translation.x;
    newFrame.origin.y += translation.y;
    CGRect bounds = _floatingWindow.bounds;
    if (newFrame.origin.x < 0) newFrame.origin.x = 0;
    if (newFrame.origin.y < 20) newFrame.origin.y = 20;
    if (newFrame.origin.x + newFrame.size.width > bounds.size.width) {
        newFrame.origin.x = bounds.size.width - newFrame.size.width;
    }
    if (newFrame.origin.y + newFrame.size.height > bounds.size.height) {
        newFrame.origin.y = bounds.size.height - newFrame.size.height - 20;
    }
    button.frame = newFrame;
    [gesture setTranslation:CGPointZero inView:_floatingWindow];
}

- (void)startRecording {
    if (_recorder.isRecording) return;
    [_recorder startRecording];
}

- (void)stopRecordingAndSave {
    if (!_recorder.isRecording) return;
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
        }
        [self->_recorder cancelRecording];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self->_recorder cancelRecording];
    }]];
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    [root presentViewController:alert animated:YES completion:nil];
}

- (void)selectMacro:(NSString *)name {
    _selectedMacroName = name;
}

- (void)playSelectedMacro {
    if (_selectedMacroName.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Macro"
                                                                       message:@"Please select a macro first"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        [root presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (_player.isPlaying) {
        [_player stop];
    }
    [_player playMacroWithName:_selectedMacroName];
}

- (void)toggleAutoRepeat:(BOOL)enabled {
    _autoRepeatEnabled = enabled;
    if (enabled && _selectedMacroName.length > 0) {
        [_macroManager setAutoRepeatMacroName:_selectedMacroName];
    } else {
        [_macroManager setAutoRepeatMacroName:nil];
    }
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
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
    [root presentViewController:alert animated:YES completion:nil];
}

@end

// ============================================================================
// TXMenuView implementation
// ============================================================================
@implementation TXMenuView {
    UITableView *_macroTable;
    UISwitch *_autoRepeatSwitch;
    UIButton *_playButton;
    UIButton *_recordButton;
    UIButton *_stopSaveButton;
    UIButton *_deleteButton;
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
    CGFloat y = 10;
    CGFloat margin = 10;
    CGFloat width = 260;
    CGFloat buttonHeight = 36;
    CGFloat spacing = 8;
    
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
    _recordButton = record;
    
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    stop.frame = CGRectMake(margin + (width - 3*margin)/2 + margin, y, (width - 3*margin)/2, buttonHeight);
    [stop setTitle:@"⏹ Save" forState:UIControlStateNormal];
    stop.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.1 alpha:1.0];
    [stop setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    stop.layer.cornerRadius = 5;
    [stop addTarget:self action:@selector(stopSaveAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:stop];
    _stopSaveButton = stop;
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
    _playButton = play;
    
    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.frame = CGRectMake(margin + (width - 3*margin)/2 + margin, y, (width - 3*margin)/2, buttonHeight);
    [del setTitle:@"🗑 Delete" forState:UIControlStateNormal];
    del.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
    [del setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    del.layer.cornerRadius = 5;
    [del addTarget:self action:@selector(deleteAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:del];
    _deleteButton = del;
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
    y += 40;
    
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
    if (menu && menu.selectedMacroName) {
        _selectedName = menu.selectedMacroName;
    } else {
        _selectedName = nil;
    }
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
    TXFloatingMenu *menu = self.menuController;
    [menu selectMacro:name];
}

#pragma mark - Actions
- (void)recordAction:(UIButton *)sender {
    [self.menuController startRecording];
}

- (void)stopSaveAction:(UIButton *)sender {
    [self.menuController stopRecordingAndSave];
}

- (void)playAction:(UIButton *)sender {
    [self.menuController playSelectedMacro];
}

- (void)deleteAction:(UIButton *)sender {
    [self.menuController deleteSelectedMacro];
}

- (void)autoRepeatToggled:(UISwitch *)sender {
    [self.menuController toggleAutoRepeat:sender.on];
}

@end

// ============================================================================
// Hooking UIWindow to capture touches
// ============================================================================
static TXRecorder *gRecorder = nil;

%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (gRecorder && [gRecorder isRecording]) {
        [gRecorder captureTouchEvent:event];
    }
}
%end

// ============================================================================
// Constructor
// ============================================================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        TXRecorder *recorder = [[TXRecorder alloc] init];
        gRecorder = recorder;
        [TXFloatingMenu sharedMenu]; // instantiate
    });
}
