#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern UIViewController *VXMakePanel(void);

static UIWindow *vxWin;
static UIWindow *vxCover;
static UIView *vxVeil;
static void (*vxOrigMKAV)(id, SEL);

static UIImage *vxLogo(void) {
    NSString *p = [NSBundle.mainBundle pathForResource:@"LaunchLogo" ofType:@"png"];
    return p ? [UIImage imageWithContentsOfFile:p] : nil;
}

static void vx_veil(UIView *host) {
    if (!host) return;
    if (!vxVeil) {
        vxVeil = [[UIView alloc] initWithFrame:host.bounds];
        vxVeil.backgroundColor = UIColor.blackColor;
        vxVeil.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIImageView *iv = [[UIImageView alloc] initWithImage:vxLogo()];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [vxVeil addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[
            [iv.centerXAnchor constraintEqualToAnchor:vxVeil.centerXAnchor],
            [iv.centerYAnchor constraintEqualToAnchor:vxVeil.centerYAnchor],
            [iv.widthAnchor constraintEqualToAnchor:vxVeil.widthAnchor multiplier:0.55]
        ]];
    }
    if (vxVeil.superview == host) {
        [host bringSubviewToFront:vxVeil];
        return;
    }
    [vxVeil removeFromSuperview];
    vxVeil.frame = host.bounds;
    [host addSubview:vxVeil];
    [host bringSubviewToFront:vxVeil];
}

static void vx_cover(void) {
    if (vxCover) return;
    vxCover = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    vxCover.windowLevel = UIWindowLevelAlert + 2;
    vxCover.backgroundColor = UIColor.blackColor;
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = UIColor.blackColor;
    UIImageView *iv = [[UIImageView alloc] initWithImage:vxLogo()];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:iv];
    [NSLayoutConstraint activateConstraints:@[
        [iv.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
        [iv.widthAnchor constraintEqualToAnchor:vc.view.widthAnchor multiplier:0.55]
    ]];
    vxCover.rootViewController = vc;
    vxCover.hidden = NO;
    [vxCover makeKeyAndVisible];
}

static void vxMKAV(UIWindow *self, SEL _cmd) {
    vxOrigMKAV(self, _cmd);
    if (self == vxWin || self == vxCover) return;
    UIViewController *r = self.rootViewController;
    if (!r) return;
    UIView *v = r.view;
    if (v) vx_veil(v);
}

static void vx_build(UIWindowScene *ws) {
    if (vxWin || !ws) return;

    vxWin = [[UIWindow alloc] initWithWindowScene:ws];
    vxWin.windowLevel = UIWindowLevelAlert + 1;
    vxWin.backgroundColor = UIColor.blackColor;
    vxWin.rootViewController = VXMakePanel();
    [vxWin makeKeyAndVisible];

    if (vxCover) {
        vxCover.windowScene = ws;
        vxCover.hidden = NO;
        [vxCover makeKeyAndVisible];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        vxVeil.hidden = YES;
        vxCover.hidden = YES;
    });
}

static void vx_watch(int n) {
    if (n > 500) return;

    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)sc;

        if (!vxWin && ws.activationState != UISceneActivationStateUnattached) vx_build(ws);

        for (UIWindow *w in ws.windows) {
            if (w == vxWin) continue;
            vx_veil(w.rootViewController.view);
        }
    }

    if (vxWin) [vxWin makeKeyAndVisible];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.004 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vx_watch(n + 1); });
}

__attribute__((constructor))
static void vx_init(void) {
    Method m = class_getInstanceMethod([UIWindow class], @selector(makeKeyAndVisible));
    if (m) {
        vxOrigMKAV = (void (*)(id, SEL))method_getImplementation(m);
        method_setImplementation(m, (IMP)vxMKAV);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        vx_cover();
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
