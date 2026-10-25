#import <Foundation/Foundation.h>
#import "../common/connection_logic.h"
#include "check.h"
#include <unistd.h>
#include <errno.h>

static size_t readBytes;
static BOOL interruptRead;
ssize_t __real_pread(int,void *,size_t,off_t);
ssize_t __wrap_pread(int fd,void *buffer,size_t size,off_t offset) {
    if (interruptRead) { interruptRead=NO; errno=EINTR; return -1; }
    ssize_t result=__real_pread(fd,buffer,size,offset);
    if (result>0) readBytes+=(size_t)result;
    return result;
}
static NSData *record(NSUInteger identifier) {
    return [[NSString stringWithFormat:@"[probe] v=1 id=%lu success=1 stage=none dns_ms=1 tcp_ms=2 transport_ms=3 protocol_ms=4 carry_ms=5 total_ms=15\n",(unsigned long)identifier] dataUsingEncoding:NSUTF8StringEncoding];
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    char path[]="/tmp/vless-probe-reader-XXXXXX";
    int fd=mkstemp(path);
    CHECK("probe-log/temporary-file",fd>=0 && unlink(path)==0);
    VCProbeLogReader *reader=[[[VCProbeLogReader alloc] initWithFileDescriptor:fd] autorelease];
    NSData *first=record(1);
    const unsigned char *bytes=[first bytes];
    for (NSUInteger i=0;i<[first length];i++) {
        CHECK("probe-log/append-byte",write(fd,bytes+i,1)==1);
        NSDictionary *report=[reader readReportAfterID:0];
        CHECK("probe-log/partial-lines-not-returned",(i+1==[first length]) == (report!=nil));
    }
    NSDictionary *saved=[[reader readReportAfterID:0] retain];
    size_t before=readBytes;
    for (NSUInteger i=0;i<20;i++) CHECK("probe-log/no-old-record",[reader readReportAfterID:1]==nil);
    CHECK("probe-log/no-reread-of-unchanged-file",readBytes==before && readBytes==[first length]);
    unsigned char invalid[]={0xff,'\n'};
    CHECK("probe-log/invalid-line",write(fd,invalid,sizeof(invalid))==sizeof(invalid));
    NSData *second=record(2);
    CHECK("probe-log/append-report",write(fd,[second bytes],[second length])==(ssize_t)[second length]);
    interruptRead=YES;
    CHECK("probe-log/invalid-utf8-does-not-hide-next-report",[[[reader readReportAfterID:1] objectForKey:@"id"] unsignedIntegerValue]==2);
    CHECK("probe-log/retained-selected-report-survives-next-read",[[saved objectForKey:@"id"] intValue]==1);
    [saved release];
    NSMutableData *large=[NSMutableData dataWithLength:100000];
    memset([large mutableBytes],'x',[large length]);
    CHECK("probe-log/append-large-prefix",write(fd,[large bytes],[large length])==(ssize_t)[large length]);
    NSData *third=record(3);
    CHECK("probe-log/append-latest-report",write(fd,[third bytes],[third length])==(ssize_t)[third length]);
    before=readBytes;
    CHECK("probe-log/bounded-tail-preserves-latest",[[[reader readReportAfterID:2] objectForKey:@"id"] intValue]==3 && readBytes-before<=65536);
    CHECK("probe-log/truncate",ftruncate(fd,0)==0 && lseek(fd,0,SEEK_SET)==0);
    CHECK("probe-log/empty-truncated-log",[reader readReportAfterID:0]==nil);
    CHECK("probe-log/restart",write(fd,[first bytes],[first length])==(ssize_t)[first length] && [[[reader readReportAfterID:0] objectForKey:@"id"] intValue]==1);
    close(fd);
    CHECK("probe-log/closed-descriptor",[reader readReportAfterID:0]==nil);
    FINISH("incremental probe log"); [pool drain]; return 0;
}
