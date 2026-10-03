#define _DEFAULT_SOURCE 1
#include "../common/control_auth.h"
#include "check.h"
#include <errno.h>
static struct stat trusted;
static int stat_failure, resolve_failure;
static char *fake_resolve(const char *path, char *out) { (void)path; if (resolve_failure) return NULL; strcpy(out, "/var/stash/Applications/vless-core.app/vless-core"); return out; }
static int fake_stat(const char *path, struct stat *out) { (void)path; if (stat_failure) { errno = ENOENT; return -1; } *out = trusted; return 0; }
int main(void) {
    const VCControlAuthOperations operations = {fake_resolve, fake_stat}; int error = 0;
    trusted.st_mode = S_IFREG | 0755; trusted.st_uid = 0; trusted.st_nlink = 1;
    const char *path = "/Applications/vless-core.app/vless-core";
    CHECK("auth/trusted-app-path", VCExecutablePathMatches(path, path, &error, &operations) == 1);
    CHECK("auth/stash-relocation", VCExecutablePathMatches("/var/stash/Applications/vless-core.app/vless-core", path, &error, &operations) == 1);
    CHECK("auth/foreign-path", VCExecutablePathMatches("/tmp/fake-app", path, &error, &operations) == 0);
    resolve_failure = 1; CHECK("auth/unresolved-path", VCExecutablePathMatches("/tmp/fake-app", path, &error, &operations) == 0); resolve_failure = 0;
    trusted.st_uid = 501; CHECK("auth/nonroot-executable", VCExecutablePathMatches(path, path, &error, &operations) == -1 && error == EPERM); trusted.st_uid = 0;
    trusted.st_mode = S_IFREG | 0777; CHECK("auth/writable-executable", VCExecutablePathMatches(path, path, &error, &operations) == -1); trusted.st_mode = S_IFREG | 0755;
    trusted.st_nlink = 2; CHECK("auth/hardlinked-executable", VCExecutablePathMatches(path, path, &error, &operations) == -1); trusted.st_nlink = 1;
    stat_failure = 1; CHECK("auth/missing-executable", VCExecutablePathMatches(path, path, &error, &operations) == -1 && error == ENOENT); stat_failure = 0;
    const char *commands[] = {"STATUS\n", "DISCONNECT\n", "CONNECT\t1080\turi\n", "ROUTING\t0;proxy;1\n", "STORE_KEY\tGET\n", "LOG\tcore\n", "EVENTS\n", "ROUTE_DIRECT_ADD\t203.0.113.1\n", "ROUTE_DIRECT_REMOVE\t203.0.113.1\n", "NATLOOK\t127.0.0.1\n"};
    for (unsigned i = 0; i < sizeof(commands) / sizeof(commands[0]); i++) {
        CHECK("auth/app-command-matrix", VCControlCommandAllowed(CONTROL_CLIENT_APP, commands[i]));
        CHECK("auth/bootstrap-command-matrix", VCControlCommandAllowed(CONTROL_CLIENT_BOOTSTRAP, commands[i]) == (i <= 1));
        CHECK("auth/core-command-matrix", VCControlCommandAllowed(CONTROL_CLIENT_CORE, commands[i]) == (i == 7 || i == 8));
        CHECK("auth/redsocks-command-matrix", VCControlCommandAllowed(CONTROL_CLIENT_REDSOCKS, commands[i]) == (i == 9));
        CHECK("auth/unauthorized-command-matrix", !VCControlCommandAllowed(CONTROL_CLIENT_UNAUTHORIZED, commands[i]));
    }
    FINISH("control authorization"); return 0;
}
