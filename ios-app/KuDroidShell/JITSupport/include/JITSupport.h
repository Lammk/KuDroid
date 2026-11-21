#import <Foundation/Foundation.h>
#include <stdbool.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif
bool KDJITCanDebug(void);
bool KDJITNeedsMemoryScript(void);
bool KDJITDebuggerConnected(void);
NSString * _Nullable KDProcessBundleIdentifier(void);
void KDPrepareDocumentAccess(void);
#ifdef __cplusplus
}
#endif

@interface KDJITExtensionSession : NSObject
+ (nullable instancetype)startWithIdentifier:(NSString *)identifier
                                    payload:(NSData *)payload
                                    started:(void (^)(void))started
                                   progress:(void (^)(NSString *))progress
                                 completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion;
- (void)cancel;
@end

typedef struct PairingSession KDPairingSession;
#ifdef __cplusplus
extern "C" {
#endif
KDPairingSession * _Nullable kudroid_pairing_start(const char *name, const char *identifier, char * _Nullable * _Nullable error);
const char * _Nullable kudroid_pairing_description(const KDPairingSession *session);
char * _Nullable kudroid_pairing_poll(const KDPairingSession *session);
void kudroid_pairing_stop(KDPairingSession * _Nullable session);
void kudroid_pairing_string_free(char * _Nullable value);
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
