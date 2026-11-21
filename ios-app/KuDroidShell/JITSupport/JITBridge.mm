#import "JITSupport.h"
#import <Security/Security.h>
#import <objc/message.h>
#include <notify.h>
#include <sys/sysctl.h>
#include <sys/proc.h>
#include "kudroid/ExecMemory.h"

extern "C" CFTypeRef SecTaskCreateFromSelf(CFAllocatorRef allocator) __attribute__((weak_import));
extern "C" CFTypeRef SecTaskCopyValueForEntitlement(CFTypeRef task, CFStringRef entitlement, CFErrorRef *error) __attribute__((weak_import));

bool KDJITCanDebug(void) {
    if (!SecTaskCreateFromSelf || !SecTaskCopyValueForEntitlement) return false;
    CFTypeRef task = SecTaskCreateFromSelf(NULL);
    if (!task) return false;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("get-task-allow"), NULL);
    bool allowed = value && CFEqual(value, kCFBooleanTrue);
    if (value) CFRelease(value);
    CFRelease(task);
    return allowed;
}

bool KDJITNeedsMemoryScript(void) {
    return kudroid::ExecMemory::TxmPresent();
}

// Check a live trace instead of the persistent code-signing flag.
bool KDJITDebuggerConnected(void) {
    int query[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc process = {};
    size_t size = sizeof(process);
    return sysctl(query, 4, &process, &size, nullptr, 0) == 0 &&
           size == sizeof(process) && (process.kp_proc.p_flag & P_TRACED) != 0;
}

@interface KDJITExtensionSession ()
@property(nonatomic, strong) id service;
@property(nonatomic, strong) NSUUID *request;
@property(nonatomic, copy) void (^completion)(NSData *, NSError *);
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL cancellationRequested;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *progressTokens;
@end

@implementation KDJITExtensionSession

+ (instancetype)startWithIdentifier:(NSString *)identifier payload:(NSData *)payload
                            started:(void (^)(void))started
                           progress:(void (^)(NSString *))progress
                         completion:(void (^)(NSData *, NSError *))completion {
    KDJITExtensionSession *session = [KDJITExtensionSession new];
    session.completion = completion;
    session.progressTokens = [NSMutableArray new];
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
    NSString *progressIdentifier = [message isKindOfClass:NSDictionary.class] ? message[@"progressIdentifier"] : nil;
    if ([progressIdentifier isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:progressIdentifier]) {
        __weak KDJITExtensionSession *weakProgressSession = session;
        for (NSString *phase in @[@"received", @"connecting", @"checkingImage", @"downloadingImage", @"mountingImage",
                                  @"verifyingImage", @"waitingForAttach", @"attached", @"preparingMemory", @"finishing"]) {
            NSString *name = [NSString stringWithFormat:@"app.jit.progress.%@.%@", progressIdentifier, phase];
            int token = 0;
            uint32_t status = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int value) {
                KDJITExtensionSession *active = weakProgressSession;
                if (active && !active.finished) progress(phase);
            });
            if (status != NOTIFY_STATUS_OK) {
                [session finish:nil error:[NSError errorWithDomain:@"JITSetup" code:4
                    userInfo:@{NSLocalizedDescriptionKey: @"Could not observe JIT helper progress. Try again."}]];
                return nil;
            }
            [session.progressTokens addObject:@(token)];
        }
    }
    Class serviceClass = NSClassFromString(@"NSExtension");
    SEL factory = NSSelectorFromString(@"extensionWithIdentifier:error:");
    NSError *error = nil;
    if ([serviceClass respondsToSelector:factory]) {
        session.service = ((id (*)(id, SEL, NSString *, NSError **))objc_msgSend)(serviceClass, factory, identifier, &error);
    }
    SEL begin = NSSelectorFromString(@"beginExtensionRequestWithInputItems:completion:");
    SEL completed = NSSelectorFromString(@"setRequestCompletionBlock:");
    SEL cancelled = NSSelectorFromString(@"setRequestCancellationBlock:");
    SEL interrupted = NSSelectorFromString(@"setRequestInterruptionBlock:");
    SEL cancel = NSSelectorFromString(@"cancelExtensionRequestWithIdentifier:");
    if (!session.service || ![session.service respondsToSelector:begin]
            || ![session.service respondsToSelector:completed]
            || ![session.service respondsToSelector:cancelled]
            || ![session.service respondsToSelector:interrupted]
            || ![session.service respondsToSelector:cancel]) {
        [session finish:nil error:error ?: [NSError errorWithDomain:@"JITSetup" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"The JIT helper is unavailable. Reinstall with app extensions preserved."}]];
        return nil;
    }
    __weak KDJITExtensionSession *weakSession = session;
    void (^reply)(NSUUID *, NSArray *) = ^(NSUUID *request, NSArray *items) {
        NSData *data = nil;
        for (id item in items) {
            if ([item isKindOfClass:NSExtensionItem.class]) {
                id value = [(NSExtensionItem *)item userInfo][@"response"];
                if ([value isKindOfClass:NSData.class]) { data = value; break; }
            }
        }
        [weakSession finish:data error:nil];
    };
    void (^failure)(NSUUID *, NSError *) = ^(NSUUID *request, NSError *error) {
        [weakSession finish:nil error:error];
    };
    void (^interruption)(NSUUID *) = ^(NSUUID *request) {
        [weakSession finish:nil error:[NSError errorWithDomain:@"JITSetup" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"The JIT helper was interrupted. Try again."}]];
    };
    ((void (*)(id, SEL, id))objc_msgSend)(session.service, completed, reply);
    ((void (*)(id, SEL, id))objc_msgSend)(session.service, cancelled, failure);
    ((void (*)(id, SEL, id))objc_msgSend)(session.service, interrupted, interruption);
    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{@"request": payload};
    void (^began)(NSUUID *) = ^(NSUUID *request) {
        dispatch_async(dispatch_get_main_queue(), ^{
            KDJITExtensionSession *active = session;
            if (!active || active.finished) return;
            active.request = request;
            if (active.cancellationRequested && request) { [active cancel]; return; }
            if (request) started();
            else [active finish:nil error:[NSError errorWithDomain:@"JITSetup" code:3
                userInfo:@{NSLocalizedDescriptionKey: @"The JIT helper could not start."}]];
        });
    };
    ((void (*)(id, SEL, NSArray *, id))objc_msgSend)(session.service, begin, @[item], began);
    return session;
}

- (void)finish:(NSData *)data error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.finished) return;
        self.finished = YES;
        for (NSNumber *token in self.progressTokens) notify_cancel(token.intValue);
        [self.progressTokens removeAllObjects];
        if (self.completion) self.completion(data, error);
        self.completion = nil;
        self.service = nil;
    });
}

- (void)cancel {
    if (self.finished) return;
    self.cancellationRequested = YES;
    if (!self.request) return;
    SEL cancel = NSSelectorFromString(@"cancelExtensionRequestWithIdentifier:");
    if (self.request && [self.service respondsToSelector:cancel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self.service, cancel, self.request);
    }
    [self finish:nil error:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
}
@end
