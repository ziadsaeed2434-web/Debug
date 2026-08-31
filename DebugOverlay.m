#import "DebugOverlay.h"

// كلاس مساعد لضمان مرور اللمسات من خلال المساحات الفارغة للنافذة
@interface PassThroughView : UIView
@end

@implementation PassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) {
        return nil;
    }
    return hitView;
}
@end

@interface DebugOverlay () <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UIWindow *overlayWindow;
@property (strong, nonatomic) UIButton *floatingButton;
@property (strong, nonatomic) UIView *panelView;
@property (strong, nonatomic) UITableView *logTableView;
@property (strong, nonatomic) NSMutableArray<NSString *> *logEntries;
@property (strong, nonatomic) UILabel *statusLabel;
@end

@implementation DebugOverlay

+ (instancetype)sharedInstance {
    static DebugOverlay *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DebugOverlay alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logEntries = [[NSMutableArray alloc] init];
        [self performSelectorOnMainThread:@selector(setupUI) withObject:nil waitUntilDone:NO];
    }
    return self;
}

- (void)showOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.overlayWindow.hidden = NO;
    });
}

- (void)hideOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.overlayWindow.hidden = YES;
    });
}

- (void)setupUI {
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive && [s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    
    if (scene) {
        self.overlayWindow = [[UIWindow alloc] initWithWindowScene:scene];
    } else {
        self.overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    
    self.overlayWindow.windowLevel = UIWindowLevelAlert + 9999;
    self.overlayWindow.backgroundColor = [UIColor clearColor];
    self.overlayWindow.userInteractionEnabled = YES;
    self.overlayWindow.hidden = NO;
    
    UIViewController *vc = [[UIViewController alloc] init];
    PassThroughView *passThroughView = [[PassThroughView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    passThroughView.backgroundColor = [UIColor clearColor];
    vc.view = passThroughView;
    
    self.overlayWindow.rootViewController = vc;
    
    // Floating Button
    self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingButton.frame = CGRectMake(20, 100, 60, 60);
    self.floatingButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.85];
    [self.floatingButton setTitle:@"🐞 ADS" forState:UIControlStateNormal];
    [self.floatingButton setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
    self.floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.floatingButton.layer.cornerRadius = 30;
    self.floatingButton.layer.borderWidth = 1.5;
    self.floatingButton.layer.borderColor = [UIColor greenColor].CGColor;
    [self.floatingButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.floatingButton addGestureRecognizer:pan];
    
    [vc.view addSubview:self.floatingButton];
    
    // Panel View
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    self.panelView = [[UIView alloc] initWithFrame:CGRectMake(20, 180, screenW - 40, screenH - 220)];
    self.panelView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
    self.panelView.layer.cornerRadius = 14;
    self.panelView.layer.borderWidth = 1.0;
    self.panelView.layer.borderColor = [UIColor darkGrayColor].CGColor;
    self.panelView.hidden = YES;
    
    // Status Header
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, screenW - 60, 60)];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont fontWithName:@"Courier" size:10];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.text = @"[ADS-DEBUG] Runtime Inspector Active\nTarget: com.codebysms";
    [self.panelView addSubview:self.statusLabel];
    
    // TableView for Logs
    self.logTableView = [[UITableView alloc] initWithFrame:CGRectMake(10, 80, screenW - 60, screenH - 320) style:UITableViewStylePlain];
    self.logTableView.backgroundColor = [UIColor clearColor];
    self.logTableView.delegate = self;
    self.logTableView.dataSource = self;
    self.logTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.panelView addSubview:self.logTableView];
    
    // Close Button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(screenW - 90, screenH - 300, 70, 30);
    [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panelView addSubview:closeBtn];
    
    [vc.view addSubview:self.panelView];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *btn = gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    CGPoint center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    btn.center = center;
    [gesture setTranslation:CGPointZero inView:btn.superview];
}

- (void)togglePanel {
    self.panelView.hidden = !self.panelView.hidden;
}

- (void)logEvent:(NSString *)category message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"HH:mm:ss.SSS";
        NSString *entry = [NSString stringWithFormat:@"[%@] %@: %@", category, [df stringFromDate:[NSDate date]], message];
        [self.logEntries insertObject:entry atIndex:0];
        if (self.logEntries.count > 100) [self.logEntries removeLastObject];
        [self.logTableView reloadData];
    });
}

- (void)logNetwork:(NSString *)host method:(NSString *)method status:(NSInteger)status sdk:(NSString *)sdk type:(NSString *)type {
    NSString *msg = [NSString stringWithFormat:@"NET | %@ | %@ %@ -> %ld (%@)", sdk, method, host, (long)status, type];
    [self logEvent:@"NETWORK" message:msg];
}

#pragma mark - TableView DataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.logEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"LogCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor greenColor];
        cell.textLabel.font = [UIFont fontWithName:@"Courier" size:10];
        cell.textLabel.numberOfLines = 0;
    }
    cell.textLabel.text = self.logEntries[indexPath.row];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 35.0;
}
@end
