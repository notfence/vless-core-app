#ifndef VC_CONNECTION_LOGIC_H
#define VC_CONNECTION_LOGIC_H
#import <Foundation/Foundation.h>
#include <sys/types.h>

@interface VCPingCancellation : NSObject {
    NSLock *_lock;
    BOOL _cancelled;
    int _socket;
    pid_t _child;
    NSString *_previousDisplay;
    NSDictionary *_diagnosticReport;
}
@property(nonatomic, copy) NSString *previousDisplay;
@property(nonatomic, copy) NSDictionary *diagnosticReport;
- (BOOL)isCancelled;
- (void)cancel;
- (BOOL)registerSocket:(int)fd;
- (void)closeSocket:(int)fd;
- (void)registerChild:(pid_t)pid;
- (pid_t)pollChild:(pid_t)pid;
- (void)forgetChild:(pid_t)pid;
@end

@interface VCPingOperation : NSInvocationOperation {
    VCPingCancellation *_cancellation;
}
@property(nonatomic, readonly) VCPingCancellation *cancellation;
- (id)initWithTarget:(id)target payload:(NSDictionary *)payload cancellation:(VCPingCancellation *)cancellation;
@end

@interface VCPingBatch : NSObject {
    NSArray *_uris;
    NSDictionary *_options;
    NSMutableSet *_pending;
    NSMutableArray *_operations;
    NSMutableDictionary *_previousDisplays;
    NSUInteger _cursor;
}
@property(nonatomic, readonly) NSDictionary *options;
@property(nonatomic, readonly) NSMutableSet *pending;
@property(nonatomic, readonly) NSMutableArray *operations;
@property(nonatomic, readonly) NSMutableDictionary *previousDisplays;
- (id)initWithURIs:(NSArray *)uris options:(NSDictionary *)options cancellation:(VCPingCancellation *)cancellation;
- (NSString *)nextURI;
@end

void VCClosePingSocket(int fd, VCPingCancellation *cancellation);
int VCWaitForPingSocket(int fd, BOOL writable, int timeout_ms, VCPingCancellation *cancellation);
typedef NS_ENUM(NSInteger, VCConnectionGate) { VCConnectionGateAllowed, VCConnectionGateBusy, VCConnectionGateSwitching };
BOOL VCConnectionActionInProgress(BOOL action, BOOL reconnect, BOOL pending);
VCConnectionGate VCConnectionToggleGate(BOOL refresh, BOOL action, BOOL reconnect);
BOOL VCConfigurationSelectionBlocked(BOOL action, BOOL connected, BOOL refresh);
BOOL VCConfigSwitchNeeded(BOOL connected, id oldURI, id newURI, BOOL oldProtected, BOOL newProtected);
void VCConnectionTouchDown(id target, BOOL connectionButton);
NSTimeInterval VCConnectedSince(NSString *response, NSTimeInterval now);
NSString *VCFormatDuration(NSTimeInterval seconds);
BOOL VCConnectionLossApplies(BOOL disconnected, BOOL connected, NSUInteger expectedGeneration, NSUInteger generation, BOOL action, NSTimeInterval expectedSince, NSTimeInterval since);
NSDictionary *VCProbeReportFromLog(NSString *text);
NSString *VCProbeFailureDisplay(NSDictionary *report);
NSString *VCProbeSummary(NSDictionary *report);
BOOL VCPingDisplayIsFailure(NSString *display);
BOOL VCPingResultIsCurrent(NSUInteger expectedGeneration, NSUInteger generation);
BOOL VCPingUpdateNetwork(id owner, NSString *signature, NSString **storedSignature, NSUInteger *generation, NSMutableDictionary *displays);
#endif
