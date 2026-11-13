#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern UIViewController *VXMakePanel(void);

static UIWindow *vxWin;
static IMP vxOrigInit;
static IMP vxOrigWillConnect;
static BOOL vxCreating;

static void vx_log(NSString *s) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    FILE *f = fopen([[dir stringByAppendingPathComponent:@"veex.log"] fileSystemRepresentation], "a");
    if (f) { fprintf(f, "%s\n", s.UTF8String); fclose(f); }
}

static void vx_build(UIWindowScene *ws) {
    if (vxWin || !ws) return;
    vxCreating = YES;
    vxWin = [[UIWindow alloc] initWithWindowScene:ws];
    vxCreating = NO;
    vxWin.windowLevel = UIWindowLevelAlert + 1;
    vxWin.backgroundColor = UIColor.blackColor;
    vxWin.rootViewController = VXMakePanel();
    [vxWin makeKeyAndVisible];
    vx_log(@"ventana arriba");
}

static void vx_watch(int n) {
    if (n > 300) return;
    if (!vxWin) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)sc;
            if (ws.activationState == UISceneActivationStateUnattached) continue;
            vx_build(ws);
        }
    }
    if (vxWin) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w != vxWin) {
                    w.hidden = YES;
                    w.alpha = 0;
                }
            }
        }
        [vxWin makeKeyAndVisible];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.006 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vx_watch(n + 1); });
}

static id vx_hook_init(id self, SEL _cmd, UIWindowScene *scene) {
    id w = ((id (*)(id, SEL, UIWindowScene *))vxOrigInit)(self, _cmd, scene);
    if (!vxCreating) {
        UIWindow *win = (UIWindow *)w;
        win.hidden = YES;
        win.alpha = 0;
        if (!vxWin) vx_build(scene);
    }
    return w;
}

static void vx_hook_connect(id self, SEL _cmd, UIScene *scene, UISceneSession *session, UISceneConnectionOptions *opts) {
    ((void (*)(id, SEL, UIScene *, UISceneSession *, UISceneConnectionOptions *))vxOrigWillConnect)(self, _cmd, scene, session, opts);
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        vx_build((UIWindowScene *)scene);
        UIWindowScene *ws = (UIWindowScene *)scene;
        for (UIWindow *w in ws.windows) {
            if (w != vxWin) {
                w.hidden = YES;
                w.alpha = 0;
            }
        }
    }
}

__attribute__((constructor))
static void vx_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Method mi = class_getInstanceMethod([UIWindow class], @selector(initWithWindowScene:));
        vxOrigInit = method_getImplementation(mi);
        method_setImplementation(mi, (IMP)vx_hook_init);
        vx_watch(0);
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneWillConnectNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n) {
            UIScene *sc = n.object;
            if (![sc isKindOfClass:[UIWindowScene class]]) return;
            vx_build((UIWindowScene *)sc);
            dispatch_async(dispatch_get_main_queue(), ^{
                for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                    if (w != vxWin) { w.hidden = YES; w.alpha = 0; }
                }
            });
        }];
    });
}
