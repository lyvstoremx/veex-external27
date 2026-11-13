#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern UIViewController *VXMakePanel(void);

static void (*orig_mkv)(id, SEL);

static void vx_mkv(id self, SEL _cmd) {
    orig_mkv(self, _cmd);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIWindow *w = (UIWindow *)self;
        UIViewController *root = w.rootViewController;
        if (!root || root.presentedViewController) return;
        UIViewController *p = VXMakePanel();
        p.modalPresentationStyle = UIModalPresentationFullScreen;
        [root presentViewController:p animated:YES completion:nil];
    });
}

__attribute__((constructor))
static void vx_init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Method m = class_getInstanceMethod([UIWindow class], @selector(makeKeyAndVisible));
        orig_mkv = (void (*)(id, SEL))method_getImplementation(m);
        method_setImplementation(m, (IMP)vx_mkv);
    });
}
