#ifndef VC_SUBSCRIPTION_TASK_H
#define VC_SUBSCRIPTION_TASK_H
#import "profile_logic.h"
#include <sys/types.h>

typedef enum {
    VCSubscriptionTaskProfiles,
    VCSubscriptionTaskAddition,
    VCSubscriptionTaskUpdate
} VCSubscriptionTaskKind;

@interface VCSubscriptionTask : NSObject <VCSubscriptionUpdateOptions> {
    NSLock *_lock;
    VCSubscriptionTaskKind _kind;
    BOOL _preserveNames;
    BOOL _cancelled;
    BOOL _committing;
    BOOL _finished;
    BOOL _notificationPending;
    NSString *_reason;
    NSString *_phase;
    NSUInteger _processed;
    NSUInteger _total;
    NSUInteger _accepted;
    NSUInteger _skipped;
    NSUInteger _duplicates;
    double _lastNotification;
    id _observer;
    SEL _selector;
    NSMutableDictionary *_metadata;
}
- (id)initWithPreserveNames:(BOOL)preserve observer:(id)observer selector:(SEL)selector;
- (id)initWithPreserveNames:(BOOL)preserve kind:(VCSubscriptionTaskKind)kind observer:(id)observer selector:(SEL)selector;
- (VCSubscriptionTaskKind)kind;
- (BOOL)cancelWithReason:(NSString *)reason;
- (BOOL)isCancelled;
- (NSString *)cancellationReason;
- (BOOL)beginCommit;
- (BOOL)isCommitting;
- (void)finish;
- (void)setPhase:(NSString *)phase;
- (void)processed:(NSUInteger)processed total:(NSUInteger)total;
- (void)addAccepted:(NSUInteger)accepted skipped:(NSUInteger)skipped;
- (void)recordDuplicate;
- (NSDictionary *)consumeProgress;
- (NSDictionary *)takePreparedMetadata;
- (NSDictionary *)preparedMetadataForURI:(NSString *)uri;
@end

VCSubscriptionTask *VCCurrentSubscriptionTask(void);
VCSubscriptionTask *VCSetCurrentSubscriptionTask(VCSubscriptionTask *task);
double VCSubscriptionMonotonicTime(void);
BOOL VCWaitSubscriptionProcess(pid_t pid, int *status, const char *bodyPath, NSUInteger maximumBytes, double timeout, VCSubscriptionTask *task, NSString **error);
NSData *VCFetchSubscriptionRequest(NSURLRequest *request, double timeout, NSURLResponse **response, NSError **error);
NSData *VCReadSubscriptionFile(NSString *path, NSString **error);
#endif
