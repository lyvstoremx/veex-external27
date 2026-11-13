#import <UIKit/UIKit.h>

extern UIViewController *VXMakePanel(void);

static UIWindow *vxWin;
static int vxTries;

static void vx_log(NSString *s) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    FILE *f = fopen([[dir stringByAppendingPathComponent:@"veex.log"] fileSystemRepresentation], "a");
    if (f) { fprintf(f, "%s\n", s.UTF8String); fclose(f); }
}

static void vx_attach(void) {
    if (vxWin) return;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)sc;
        if (ws.activationState == UISceneActivationStateUnattached) continue;
        vxWin = [[UIWindow alloc] initWithWindowScene:ws];
        vxWin.windowLevel = UIWindowLevelAlert + 1;
        vxWin.backgroundColor = UIColor.whiteColor;
        vxWin.rootViewController = VXMakePanel();
        [vxWin makeKeyAndVisible];
        vx_log(@"ventana arriba");
        return;
    }
}

static void vx_wait(void) {
    vx_attach();
    if (vxWin) return;
    if (++vxTries > 200) { vx_log(@"sin escena"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vx_wait(); });
}

__attribute__((constructor))
static void vx_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UISceneWillConnectNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n) { vx_attach(); }];
        vx_wait();
    });
}
