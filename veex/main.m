#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern UIViewController *VXMakePanel(void);

static UIWindow *vxWin;
static IMP vxOrigInit;
static BOOL vxCreating;

static void vx_log(NSString *s) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    FILE *f = fopen([[dir stringByAppendingPathComponent:@"veex.log"] fileSystemRepresentation], "a");
    if (f) { fprintf(f, "%s\n", s.UTF8String); fclose(f); }
}

static void vx_tick(int n) {
    if (n > 420) return;

    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)sc;

        for (UIWindow *w in ws.windows) {
            if (w != vxWin) {
                w.hidden = YES;
                w.alpha = 0;
            }
        }

        if (!vxWin && ws.activationState != UISceneActivationStateUnattached) {
            vxCreating = YES;
            vxWin = [[UIWindow alloc] initWithWindowScene:ws];
            vxCreating = NO;
            vxWin.windowLevel = UIWindowLevelAlert + 1;
            vxWin.backgroundColor = UIColor.blackColor;
            vxWin.rootViewController = VXMakePanel();
            [vxWin makeKeyAndVisible];
            vx_log(@"ventana arriba");
        }
    }

    if (vxWin) [vxWin makeKeyAndVisible];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.008 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vx_tick(n + 1); });
}

static id vx_hook_init(id self, SEL _cmd, UIWindowScene *scene) {
    id w = ((id (*)(id, SEL, UIWindowScene *))vxOrigInit)(self, _cmd, scene);
    if (!vxCreating) {
        UIWindow *win = (UIWindow *)w;
        win.hidden = YES;
        win.alpha = 0;
    }
    return w;
}

__attribute__((constructor))
static void vx_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Method m = class_getInstanceMethod([UIWindow class], @selector(initWithWindowScene:));
        vxOrigInit = method_getImplementation(m);
        method_setImplementation(m, (IMP)vx_hook_init);
        vx_tick(0);
    });
}
