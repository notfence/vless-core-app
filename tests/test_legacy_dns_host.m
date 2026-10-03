#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <assert.h>
static int vc_root_fstat(int fd, struct stat *st) { int rc = fstat(fd, st); if (!rc) st->st_uid = 0; return rc; }
static int vc_root_stat(const char *path, struct stat *st) { int rc = stat(path, st); if (!rc) st->st_uid = 0; return rc; }
#define fstat(fd, st) vc_root_fstat(fd, st)
#define stat(path, st) vc_root_stat(path, st)
#define VC_HOST_LEGACY_TEST 1
#define VC_LEGACY_DNS_PATH "state/dns.plist"
#define VC_LEGACY_DNS_DIRECTORY "state"
#define main vc_existing_dns_tests
#include "legacy_dns_test.c"
#undef main
#undef fstat
#undef stat
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    char directory[] = "/tmp/vless-host-dns.XXXXXX";
    assert(mkdtemp(directory) && chdir(directory) == 0 && mkdir("state", 0700) == 0);
    int rc = vc_existing_dns_tests();
    assert(rmdir("state") == 0 && chdir("/") == 0 && rmdir(directory) == 0);
    [pool drain]; return rc;
}
