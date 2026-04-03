#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static const char *kVPNIconStatePath = "/var/mobile/Library/Preferences/com.vlesscore.vpnicon.state";

// Quarter-screen style glitches are often triggered by unsafe SpringBoard-tweak timing.
// Keep updates serialized, delayed, and only apply real state transitions.
static BOOL gSpringBoardDidFinishLaunching = NO;
static BOOL gApplyScheduled = NO;
static BOOL gHasPendingState = NO;
static BOOL gPendingState = NO;
static BOOL gHasLastAppliedState = NO;
static BOOL gLastAppliedState = NO;

static BOOL ReadVPNState(void) {
    FILE *fp = fopen(kVPNIconStatePath, "r");
    if (!fp) return NO;
    int c = fgetc(fp);
    fclose(fp);
    return c == '1';
}

static BOOL CallBoolSelectorIfExists(id obj, const char *selName, BOOL value) {
    if (!obj || !selName || !*selName) return NO;

    SEL sel = sel_registerName(selName);
    if (![obj respondsToSelector:sel]) return NO;

    IMP imp = [obj methodForSelector:sel];
    if (!imp) return NO;

    void (*func)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))imp;
    func(obj, sel, value);
    return YES;
}

static BOOL ReadBoolSelectorIfExists(id obj, const char *selName, BOOL *outValue) {
    if (!obj || !selName || !*selName || !outValue) return NO;

    SEL sel = sel_registerName(selName);
    if (![obj respondsToSelector:sel]) return NO;

    IMP imp = [obj methodForSelector:sel];
    if (!imp) return NO;

    BOOL (*func)(id, SEL) = (BOOL (*)(id, SEL))imp;
    *outValue = func(obj, sel);
    return YES;
}

static BOOL CallVoidSelectorIfExists(id obj, const char *selName) {
    if (!obj || !selName || !*selName) return NO;

    SEL sel = sel_registerName(selName);
    if (![obj respondsToSelector:sel]) return NO;

    IMP imp = [obj methodForSelector:sel];
    if (!imp) return NO;

    void (*func)(id, SEL) = (void (*)(id, SEL))imp;
    func(obj, sel);
    return YES;
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

static BOOL ApplyVPNIconStateImpl(BOOL enabled) {
    @try {
        id telephony = SharedObjectForClassName("SBTelephonyManager", "sharedTelephonyManager", "sharedInstance");
        if (!telephony) return NO;

        BOOL current = NO;
        if (ReadBoolSelectorIfExists(telephony, "isUsingVPNConnection", &current) ||
            ReadBoolSelectorIfExists(telephony, "_isUsingVPNConnection", &current)) {
            if (current == enabled) return YES;
        }

        BOOL applied = NO;
        if (CallBoolSelectorIfExists(telephony, "setIsUsingVPNConnection:", enabled)) {
            applied = YES;
        } else if (CallBoolSelectorIfExists(telephony, "_setIsUsingVPNConnection:", enabled)) {
            applied = YES;
        }
        if (!applied) return NO;

        // Some builds update status bar lazily; poke a refresh when available.
        (void)CallVoidSelectorIfExists(telephony, "updateSpringBoard");
        return YES;
    }
    @catch (NSException *ex) {
        (void)ex;
        return NO;
    }
}

@interface VLESSCoreVPNIconBridge : NSObject
+ (void)queueVPNIconState;
+ (void)flushPendingVPNIconState;
+ (void)noteSpringBoardDidFinishLaunching:(NSNotification *)note;
+ (void)scheduleReadyFallback;
+ (void)markSpringBoardReadyFallback;
@end

@implementation VLESSCoreVPNIconBridge

+ (void)queueVPNIconState {
    if (!gSpringBoardDidFinishLaunching) return;
    if (gApplyScheduled) return;

    gApplyScheduled = YES;
    [self performSelector:@selector(flushPendingVPNIconState)
               withObject:nil
               afterDelay:0.15];
}

+ (void)flushPendingVPNIconState {
    gApplyScheduled = NO;
    if (!gSpringBoardDidFinishLaunching || !gHasPendingState) return;

    BOOL enabled = gPendingState;
    gHasPendingState = NO;

    if (gHasLastAppliedState && gLastAppliedState == enabled) return;

    if (!ApplyVPNIconStateImpl(enabled)) {
        gPendingState = enabled;
        gHasPendingState = YES;
        if (!gApplyScheduled) {
            gApplyScheduled = YES;
            [self performSelector:@selector(flushPendingVPNIconState)
                       withObject:nil
                       afterDelay:1.0];
        }
        return;
    }

    gLastAppliedState = enabled;
    gHasLastAppliedState = YES;
}

+ (void)noteSpringBoardDidFinishLaunching:(NSNotification *)note {
    (void)note;
    gSpringBoardDidFinishLaunching = YES;
    [self flushPendingVPNIconState];
}

+ (void)scheduleReadyFallback {
    [self performSelector:@selector(markSpringBoardReadyFallback)
               withObject:nil
               afterDelay:1.0];
}

+ (void)markSpringBoardReadyFallback {
    if (!gSpringBoardDidFinishLaunching) {
        gSpringBoardDidFinishLaunching = YES;
    }
    [self flushPendingVPNIconState];
}

@end

static void ApplyVPNIconState(BOOL enabled) {
    gPendingState = enabled;
    gHasPendingState = YES;

    if ([NSThread isMainThread]) {
        [VLESSCoreVPNIconBridge queueVPNIconState];
    } else {
        [VLESSCoreVPNIconBridge performSelectorOnMainThread:@selector(queueVPNIconState)
                                                 withObject:nil
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

        [[NSNotificationCenter defaultCenter] addObserver:[VLESSCoreVPNIconBridge class]
                                                 selector:@selector(noteSpringBoardDidFinishLaunching:)
                                                     name:UIApplicationDidFinishLaunchingNotification
                                                   object:nil];

        if ([NSThread isMainThread]) {
            [VLESSCoreVPNIconBridge scheduleReadyFallback];
        } else {
            [VLESSCoreVPNIconBridge performSelectorOnMainThread:@selector(scheduleReadyFallback)
                                                     withObject:nil
                                                  waitUntilDone:NO];
        }

        ApplyVPNIconState(ReadVPNState());
    }
}
