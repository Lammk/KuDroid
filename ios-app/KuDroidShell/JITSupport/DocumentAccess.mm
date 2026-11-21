#import "JITSupport.h"
#import <Security/Security.h>
#import <objc/runtime.h>

extern "C" CFTypeRef SecTaskCreateFromSelf(CFAllocatorRef) __attribute__((weak_import));
extern "C" CFTypeRef SecTaskCopyValueForEntitlement(CFTypeRef, CFStringRef, CFErrorRef *) __attribute__((weak_import));

NSString *KDProcessBundleIdentifier(void) {
    if (!SecTaskCreateFromSelf || !SecTaskCopyValueForEntitlement) return nil;
    CFTypeRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) return nil;
    CFTypeRef raw = SecTaskCopyValueForEntitlement(task, CFSTR("application-identifier"), nullptr);
    CFRelease(task);
    if (!raw) return nil;
    NSString *identifier = CFGetTypeID(raw) == CFStringGetTypeID() ? [(__bridge NSString *)raw copy] : nil;
    CFRelease(raw);
    NSArray<NSString *> *components = [identifier componentsSeparatedByString:@"."];
    if (components.count < 2) return nil;
    return [[components subarrayWithRange:NSMakeRange(1, components.count - 1)] componentsJoinedByString:@"."];
}

static NSString *documentHost;
static void (*setDocumentHost)(id, SEL, NSString *);

static void applyDocumentHost(id configuration, SEL selector, NSString *requested) {
    setDocumentHost(configuration, selector, documentHost ?: requested);
}

// File-provider access belongs to the signed process identity.
void KDPrepareDocumentAccess(void) {
    if (setDocumentHost) return;
    NSString *identifier = KDProcessBundleIdentifier();
    if (!identifier || [identifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) return;
    Method setter = class_getInstanceMethod(NSClassFromString(@"DOCConfiguration"), NSSelectorFromString(@"setHostIdentifier:"));
    if (!setter) return;
    documentHost = identifier;
    setDocumentHost = reinterpret_cast<void (*)(id, SEL, NSString *)>(method_getImplementation(setter));
    method_setImplementation(setter, reinterpret_cast<IMP>(applyDocumentHost));
}
