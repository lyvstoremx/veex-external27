#import <UIKit/UIKit.h>

extern UIViewController *VXMakePanel(void);

static UIWindow *vxWin;
static int vxTries;

static void vx_log(NSString *s) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    FILE *f = fopen([[dir stringByAppendingPathComponent:@"veex.log"] fileSystemRepresentation], "a");
    if (f) { fprintf(f, "%s\n", s.UTF8String); fclose(f); }
}

static void vx_attach(void);

static void vx_wait(void) {
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]] &&
            ((UIWindowScene *)sc).activationState != UISceneActivationStateUnattached) {
            vx_attach();
            return;
        }
    }
    if (++vxTries > 80) { vx_log(@"sin escena"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vx_wait(); });
}

static void vx_attach(void) {
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        vxWin = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)sc];
        vxWin.windowLevel = UIWindowLevelAlert + 1;
        vxWin.backgroundColor = UIColor.whiteColor;
        vxWin.rootViewController = VXMakePanel();
        [vxWin makeKeyAndVisible];
        vx_log(@"ventana arriba");
        return;
    }
}

__attribute__((constructor))
static void vx_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ vx_wait(); });
}
