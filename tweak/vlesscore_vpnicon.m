#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static const char *kVPNIconStatePath = "/var/mobile/Library/Preferences/com.vlesscore.vpnicon.state";

static BOOL ReadVPNState(void) {
    FILE *fp = fopen(kVPNIconStatePath, "r");
    if (!fp) return NO;
    int c = fgetc(fp);
    fclose(fp);
    return c == '1';
}

static void CallBoolSelectorIfExists(id obj, const char *selName, BOOL value) {
    if (!obj || !selName || !*selName) return;

    SEL sel = sel_registerName(selName);
    if (![obj respondsToSelector:sel]) return;

    IMP imp = [obj methodForSelector:sel];
    if (!imp) return;

    void (*func)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))imp;
    func(obj, sel, value);
}

static id SharedObjectForClassName(const char *className, const char *selA, const char *selB) {
    Class cls = NSClassFromString([NSString stringWithUTF8String:className]);
    if (!cls) return nil;

    SEL s = sel_registerName(selA);
    if ([cls respondsToSelector:s]) {
        IMP imp = [cls methodForSelector:s];
        if (imp) {
            id (*fn)(id, SEL) = (id (*)(id, SEL))imp;
            id out = fn(cls, s);
            if (out) return out;
        }
    }

    if (selB && *selB) {
        SEL s2 = sel_registerName(selB);
        if ([cls respondsToSelector:s2]) {
            IMP imp2 = [cls methodForSelector:s2];
            if (imp2) {
                id (*fn2)(id, SEL) = (id (*)(id, SEL))imp2;
                return fn2(cls, s2);
            }
        }
    }

    return nil;
}

static void ApplyVPNIconStateImpl(BOOL enabled) {
    @try {
        id telephony = SharedObjectForClassName("SBTelephonyManager", "sharedTelephonyManager", "sharedInstance");
        CallBoolSelectorIfExists(telephony, "setIsUsingVPNConnection:", enabled);
        CallBoolSelectorIfExists(telephony, "_setIsUsingVPNConnection:", enabled);
    }
    @catch (NSException *ex) {
        (void)ex;
    }
}

@interface VLESSCoreVPNIconBridge : NSObject
+ (void)applyVPNIconStateFromNumber:(NSNumber *)value;
@end

@implementation VLESSCoreVPNIconBridge
+ (void)applyVPNIconStateFromNumber:(NSNumber *)value {
    ApplyVPNIconStateImpl([value boolValue]);
}
@end

static void ApplyVPNIconState(BOOL enabled) {
    if ([NSThread isMainThread]) {
        ApplyVPNIconStateImpl(enabled);
    } else {
        [VLESSCoreVPNIconBridge performSelectorOnMainThread:@selector(applyVPNIconStateFromNumber:)
                                                 withObject:[NSNumber numberWithBool:enabled]
                                              waitUntilDone:NO];
    }
}

static void VPNIconChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    ApplyVPNIconState(ReadVPNState());
}

__attribute__((constructor))
static void InitVLESSCoreVPNIconTweak(void) {
    @autoreleasepool {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        VPNIconChanged,
                                        CFSTR("com.vlesscore.vpnicon.changed"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        ApplyVPNIconState(ReadVPNState());
    }
}
