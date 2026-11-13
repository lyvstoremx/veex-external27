#import <UIKit/UIKit.h>

extern UIViewController *VXMakePanel(void);

static UIWindow *vxWin;

static UIImage *vxLogo(void) {
    NSString *p = [NSBundle.mainBundle pathForResource:@"LaunchLogo" ofType:@"png"];
    return p ? [UIImage imageWithContentsOfFile:p] : nil;
}

static UIViewController *vxBlack(void) {
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;
    UIImageView *iv = [[UIImageView alloc] initWithImage:vxLogo()];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:iv];
    [NSLayoutConstraint activateConstraints:@[
        [iv.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
        [iv.widthAnchor constraintEqualToAnchor:vc.view.widthAnchor multiplier:0.72]
    ]];
    return vc;
}

static void vx_build(UIWindowScene *ws) {
    if (vxWin || !ws) return;
    vxWin = [[UIWindow alloc] initWithWindowScene:ws];
    vxWin.windowLevel = UIWindowLevelAlert + 1;
    vxWin.backgroundColor = UIColor.blackColor;
    vxWin.rootViewController = VXMakePanel();
    [vxWin makeKeyAndVisible];
}

static void vx_watch(int n) {
    if (n > 500) return;

    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)sc;

        if (!vxWin && ws.activationState != UISceneActivationStateUnattached) vx_build(ws);

        for (UIWindow *w in ws.windows) {
            if (w == vxWin) continue;
            if (![w.rootViewController isKindOfClass:NSClassFromString(@"VXBlackVC")]) {
                UIViewController *b = vxBlack();
                object_setClass(b, NSClassFromString(@"VXBlackVC"));
                w.rootViewController = b;
            }
        }
    }

    if (vxWin) [vxWin makeKeyAndVisible];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.004 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vx_watch(n + 1); });
}

__attribute__((constructor))
static void vx_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        vx_watch(0);
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneWillConnectNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n) {
            if ([[n object] isKindOfClass:[UIWindowScene class]]) vx_build((UIWindowScene *)[n object]);
        }];
    });
}
