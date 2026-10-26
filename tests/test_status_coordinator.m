#import <Foundation/Foundation.h>
#include "check.h"
@interface NSObject (VCStatusTest)
- (id)initWithCommand:(NSString *(*)(NSString *))command;
- (NSString *)readStatus;
@end
static NSCondition *gate;
static NSUInteger calls,waiting,finished,matched;
static BOOL releaseCommand,throwCommand;
static NSString *command(NSString *value) {
    [gate lock]; calls++; [gate broadcast];
    while (!releaseCommand) [gate wait];
    BOOL fail=throwCommand; [gate unlock];
    if (fail) [NSException raise:@"SyntheticStatusFailure" format:@"test"];
    return [value isEqual:@"STATUS\n"] ? @"OK connected socks=1080" : nil;
}
@interface WaitCondition : NSCondition
@end
@implementation WaitCondition
- (void)wait { [gate lock]; waiting++; [gate broadcast]; [gate unlock]; [super wait]; }
@end
@interface StatusWorker : NSObject { id _coordinator; }
- (id)initWithCoordinator:(id)coordinator;
- (void)run;
@end
@implementation StatusWorker
- (id)initWithCoordinator:(id)coordinator { if ((self=[super init])) _coordinator=[coordinator retain]; return self; }
- (void)dealloc { [_coordinator release]; [super dealloc]; }
- (void)run {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    NSString *value=nil;
    @try { value=[_coordinator readStatus]; } @catch (NSException *exception) { (void)exception; }
    [gate lock]; finished++; if ([value isEqual:@"OK connected socks=1080"]) matched++; [gate broadcast]; [gate unlock]; [pool drain];
}
@end
static void waitFor(NSUInteger *value,NSUInteger target) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    [gate lock]; while (*value<target && [gate waitUntilDate:deadline]) {}
    CHECK("status/bounded-completion",*value>=target); [gate unlock];
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    Class cls=NSClassFromString(@"VCStatusCoordinator"); CHECK("status/coordinator-implemented",cls!=Nil);
    gate=[[NSCondition alloc] init];
    id coordinator=[[[cls alloc] initWithCommand:command] autorelease];
    WaitCondition *condition=[[[WaitCondition alloc] init] autorelease];
    [coordinator setValue:condition forKey:@"condition"];
    StatusWorker *worker=[[[StatusWorker alloc] initWithCoordinator:coordinator] autorelease];
    for (NSUInteger repetition=0;repetition<6;repetition++) {
        calls=waiting=finished=matched=0; releaseCommand=NO;
        throwCommand=repetition==5;
        [NSThread detachNewThreadSelector:@selector(run) toTarget:worker withObject:nil]; waitFor(&calls,1);
        for (NSUInteger i=1;i<16;i++) [NSThread detachNewThreadSelector:@selector(run) toTarget:worker withObject:nil];
        waitFor(&waiting,15);
        [gate lock]; releaseCommand=YES; [gate broadcast]; [gate unlock]; waitFor(&finished,16);
        CHECK("status/one-command-for-concurrent-consumers",calls==1 && matched==(throwCommand ? 0 : 16));
        throwCommand=NO;
        CHECK("status/no-long-lived-status-cache",[[coordinator readStatus] isEqual:@"OK connected socks=1080"] && calls==2);
    }
    throwCommand=YES;
    @try { [coordinator readStatus]; } @catch (NSException *exception) { CHECK("status/failure-propagated",[exception.name isEqual:@"SyntheticStatusFailure"]); }
    throwCommand=NO;
    CHECK("status/recovery-after-exception",[[coordinator readStatus] isEqual:@"OK connected socks=1080"]);
    id empty=[[[cls alloc] initWithCommand:NULL] autorelease];
    CHECK("status/missing-command-releases-waiters",[empty readStatus]==nil && [empty readStatus]==nil);
    FINISH("status coordinator"); [gate release]; [pool drain]; return 0;
}
