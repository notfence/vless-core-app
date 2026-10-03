#define _DEFAULT_SOURCE 1
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <assert.h>
static int vc_root_fstat(int fd, struct stat *st) { int rc = fstat(fd, st); if (!rc) st->st_uid = 0; return rc; }
#define fstat(fd, st) vc_root_fstat(fd, st)
#define VC_HOST_LEGACY_TEST 1
#define VC_LOOPBACK_STATE_PATH "state/routes"
#define main vc_existing_route_tests
#include "legacy_loopback_test.c"
#undef main
#undef fstat
int main(void) {
    char directory[] = "/tmp/vless-host-routes.XXXXXX";
    assert(mkdtemp(directory) && chdir(directory) == 0 && mkdir("state", 0700) == 0);
    int rc = vc_existing_route_tests();
    assert(rmdir("state") == 0 && chdir("/") == 0 && rmdir(directory) == 0);
    return rc;
}
