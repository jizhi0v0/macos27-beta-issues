//
//  RemoteViewCrashGuard.m — crash guard *and* probe for issue #17
//  https://github.com/jizhi0v0/macos27-beta-issues/issues/17
//
//  Apple ViewBridge throws an uncaught NSInternalInconsistencyException when a
//  containing-window ordering notification reaches an NSRemoteView whose own
//  window no longer matches the notification's object. Disassembly of
//  ViewBridge on macOS 27.0 beta5 (26A5406e) shows the whole predicate is:
//
//      -[NSRemoteView containingWindowWillOrderOnScreen:](self, _cmd, note) {
//          if (![self isValid]) return;                              // +32
//          if ([self window] != [note object]) {                     // +44/+56/+64
//              e = handleFailureIn(..., NSRemoteView.m, 4232,
//                                  @"%@ notified of %@ but expected %@");  // +208
//              [e raise];                                            // +212 -> ret addr +216
//          }
//          [self _expectWindowOrderingState:0 andAdvanceTo:2 caller:...];
//      }
//
//  WHY THIS DIFFERS FROM THE VERSION CIRCULATING ON THE FORUMS
//  (https://developer.apple.com/forums/thread/837342):
//
//  1. That version guards ONLY containingWindowWillOrderOnScreen:. There are at
//     least three assertion sites on this path — the Will handler has one, and
//     -[NSRemoteView containingWindowDidOrderOnScreen:] has TWO more (+220 and
//     +260), downstream of its own `[self window] != [note object]` compare at
//     +64. If the bad state survives into the Did handler, the forum guard does
//     not stop it. This one wraps both.
//
//  2. It is also a probe. Every invocation is logged with isValid / window /
//     notification object / whether they matched, so a quiet period produces a
//     positive record ("the bad input never occurred") rather than mere absence
//     of crashes. Suppressed assertions log the full reason string, which names
//     the remote view's *service* and the containing window's class — something
//     our own 32 crash reports structurally could not capture.
//
//  Not a fix: swallowing the assertion leaves the view in the state AppKit
//  considered inconsistent. Skipping the Will handler's
//  _expectWindowOrderingState:andAdvanceTo: does NOT cascade into another
//  crash — that method has zero assertion sites and only calls vbLog on
//  mismatch (verified by disassembly) — but whether the panel then draws and
//  behaves correctly is UNVERIFIED here.
//
//  This swizzles a private class and a private method. NSRemoteView is not API.
//  Weigh that before shipping, especially for a Mac App Store submission, and
//  remove it once Apple ships the fix.
//
//  Usage:  [RemoteViewCrashGuard install];   // early, e.g. applicationWillFinishLaunching:
//  Read:   log stream --predicate 'subsystem == "dev.jizhi.remoteviewguard"'
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <dlfcn.h>

@interface RemoteViewCrashGuard : NSObject
+ (void)install;
@end

@implementation RemoteViewCrashGuard

static os_log_t GuardLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("dev.jizhi.remoteviewguard", "viewbridge"); });
    return log;
}

/// Only macOS 27 is known to carry this bug. Narrow or remove once Apple ships a fix.
+ (BOOL)shouldInstall {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27;
}

/// -isValid is private on NSRemoteView; read it defensively and report "?" if absent
/// rather than assuming it exists. It is the first thing the real method checks.
static NSString *IsValidDescription(id remoteView) {
    SEL sel = NSSelectorFromString(@"isValid");
    if (![remoteView respondsToSelector:sel]) return @"?";
    NSMethodSignature *sig = [remoteView methodSignatureForSelector:sel];
    if (strcmp(sig.methodReturnType, @encode(BOOL)) != 0) return @"?";
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.selector = sel;
    [inv invokeWithTarget:remoteView];
    BOOL valid = NO;
    [inv getReturnValue:&valid];
    return valid ? @"YES" : @"NO";
}

/// Wrap one notification-handling selector: log the inputs that decide the
/// assertion, then call through, suppressing only this specific assertion.
+ (void)guardSelectorNamed:(NSString *)selName onClass:(Class)cls {
    SEL sel = NSSelectorFromString(selName);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        os_log_error(GuardLog(), "not installed: %{public}@ not found", selName);
        return;
    }
    IMP originalIMP = method_getImplementation(method);

    // imp_implementationWithBlock drops _cmd: the block receives (self, arg1).
    // The argument is an NSNotification, not an NSWindow — the forum version
    // types it as NSWindow*, which is harmless but misleading.
    IMP guarded = imp_implementationWithBlock(^(NSView *rv, NSNotification *note) {
        id noteObject = note.object;
        NSWindow *ownWindow = rv.window;   // -window is public API on NSView
        BOOL matched = (ownWindow == noteObject);

        // The probe half: this line is the point of the whole file. A run with
        // many "match=YES" lines and no "match=NO" is positive evidence that
        // the bad input never arose — unlike "no crash", which proves nothing.
        // os_log_info, deliberately NOT os_log_debug: debug-level messages are
        // memory-only and routinely dropped, so `log show` would come back empty
        // and the probe half of this file would record nothing. Verified on
        // 26A5406e — with os_log_debug these lines never appeared.
        os_log_info(GuardLog(),
                    "%{public}@ rv=%p isValid=%{public}@ window=%p note.object=%p match=%{public}s",
                    selName, rv, IsValidDescription(rv), ownWindow, noteObject,
                    matched ? "YES" : "NO");

        if (!matched) {
            os_log_error(GuardLog(),
                         "BAD STATE about to hit the assertion in %{public}@: "
                         "window=%{public}@ note.object=%{public}@",
                         selName, ownWindow, noteObject);
        }

        @try {
            ((void (*)(id, SEL, NSNotification *))originalIMP)(rv, sel, note);
        } @catch (NSException *e) {
            BOOL ours = [e.name isEqualToString:NSInternalInconsistencyException]
                     && [e.reason containsString:@"NSRemoteView"];
            if (!ours) @throw;
            // e.reason carries the service name and the containing window class.
            os_log_fault(GuardLog(), "SUPPRESSED in %{public}@: %{public}@", selName, e.reason);
        }
    });

    method_setImplementation(method, guarded);
    os_log_info(GuardLog(), "guarded %{public}@", selName);
}

+ (void)install {
    if (![self shouldInstall]) return;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // ViewBridge is loaded lazily — the first remote view (open/save panel,
        // QuickLook, share sheet, status item, autofill…) pulls it in. Install
        // this guard at the recommended time (applicationWillFinishLaunching:)
        // and NSClassFromString returns nil, so the guard silently does nothing.
        // Verified on 26A5406e: without this dlopen the install logs
        // "NSRemoteView not found" and no swizzle happens. The version
        // circulating on the forums has the same bug and no log to reveal it.
        // dlopen works even though the binary lives only in the dyld shared
        // cache and not on disk.
        if (!NSClassFromString(@"NSRemoteView")) {
            dlopen("/System/Library/PrivateFrameworks/ViewBridge.framework/ViewBridge", RTLD_LAZY);
        }
        Class cls = NSClassFromString(@"NSRemoteView");
        if (!cls) {
            os_log_error(GuardLog(), "not installed: NSRemoteView not found even after loading ViewBridge");
            return;
        }
        // Both handlers compare [self window] against the notification object and
        // assert on mismatch. Guarding only the first one leaves two live
        // assertion sites in the second.
        [self guardSelectorNamed:@"containingWindowWillOrderOnScreen:" onClass:cls];
        [self guardSelectorNamed:@"containingWindowDidOrderOnScreen:" onClass:cls];
        os_log_info(GuardLog(), "installed for macOS %ld.x",
                    (long)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion);
    });
}

@end
