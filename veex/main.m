#import <UIKit/UIKit.h>

extern UIViewController *VXMakePanel(void);

static void vx_log(NSString *s) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *p = [dir stringByAppendingPathComponent:@"veex.log"];
    FILE *f = fopen(p.fileSystemRepresentation, "a");
    if (f) { fprintf(f, "%s\n", s.UTF8String); fclose(f); }
}

static UIWindow *vx_key(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return nil;
}

static void vx_try(int n) {
    UIViewController *root = vx_key().rootViewController;
    if (root && !root.presentedViewController) {
        vx_log(@"presentando");
        UIViewController *p = VXMakePanel();
        p.modalPresentationStyle = UIModalPresentationFullScreen;
        [root presentViewController:p animated:YES completion:nil];
        return;
    }
    if (n > 40) { vx_log(@"rendido sin ventana"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vx_try(n + 1); });
}

__attribute__((constructor))
static void vx_init(void) {
    vx_log(@"constructor vivo");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ vx_try(0); });
}
