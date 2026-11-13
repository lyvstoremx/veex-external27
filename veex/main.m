#import <UIKit/UIKit.h>

extern UIViewController *VXMakePanel(void);

static UIWindow *vxWin;
static UIView *vxVeil;

static UIImage *vxLogo(void) {
    NSString *p = [NSBundle.mainBundle pathForResource:@"LaunchLogo" ofType:@"png"];
    return p ? [UIImage imageWithContentsOfFile:p] : nil;
}

static void vx_veilOn(UIWindow *w) {
    if (!w) return;
    if (!vxVeil) {
        vxVeil = [[UIView alloc] initWithFrame:w.bounds];
        vxVeil.backgroundColor = UIColor.blackColor;
        vxVeil.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIImageView *iv = [[UIImageView alloc] initWithImage:vxLogo()];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [vxVeil addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[
            [iv.centerXAnchor constraintEqualToAnchor:vxVeil.centerXAnchor],
            [iv.centerYAnchor constraintEqualToAnchor:vxVeil.centerYAnchor],
            [iv.widthAnchor constraintEqualToAnchor:vxVeil.widthAnchor multiplier:0.7]
        ]];
    }
    vxVeil.frame = w.bounds;
    [w addSubview:vxVeil];
    [w bringSubviewToFront:vxVeil];
}

static void vx_build(UIWindowScene *ws) {
    if (vxWin || !ws) return;
    vxWin = [[UIWindow alloc] initWithWindowScene:ws];
    vxWin.windowLevel = UIWindowLevelAlert + 1;
    vxWin.backgroundColor = UIColor.blackColor;
    vxWin.rootViewController = VXMakePanel();
    [vxWin makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vxVeil.hidden = YES; });
}

static void vx_watch(int n) {
    if (n > 400) return;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)sc;
        if (ws.activationState == UISceneActivationStateUnattached) continue;
        if (!vxWin) vx_build(ws);
        for (UIWindow *w in ws.windows) {
            if (w == vxWin) continue;
            w.hidden = NO;
            w.alpha = 1;
            vx_veilOn(w);
        }
    }
    if (vxWin) [vxWin makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.006 * NSEC_PER_SEC)),
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
