#define _XOPEN_SOURCE 700
#include "control_auth.h"
#include <string.h>
#include <limits.h>
#include <errno.h>

int VCExecutablePathMatches(const char *actual,
                                   const char *expected,
                                   int *trust_error, const VCControlAuthOperations *operations) {
    if (trust_error) *trust_error = 0;
    if (!actual || !expected) return 0;

    int path_matches = strcmp(actual, expected) == 0;
    if (!path_matches) {
        char expected_resolved[PATH_MAX];
        if (!operations->resolve(expected, expected_resolved) ||
            strcmp(actual, expected_resolved) != 0) {
            return 0;
        }
    }

    struct stat trusted;
    if (operations->file_info(expected, &trusted) != 0) {
        if (trust_error) *trust_error = errno;
        return -1;
    }
    if (!S_ISREG(trusted.st_mode) ||
        trusted.st_uid != 0 ||
        trusted.st_nlink != 1 ||
        (trusted.st_mode & 022) != 0) {
        if (trust_error) *trust_error = EPERM;
        return -1;
    }
    return 1;
}

int VCControlCommandAllowed(control_client_t client, const char *command) {
    if (client == CONTROL_CLIENT_APP) return 1;
    if (client == CONTROL_CLIENT_BOOTSTRAP) return strncmp(command, "STATUS", 6) == 0 || strncmp(command, "DISCONNECT", 10) == 0;
    if (client == CONTROL_CLIENT_CORE) return strncmp(command, "ROUTE_DIRECT_ADD\t", 17) == 0 || strncmp(command, "ROUTE_DIRECT_REMOVE\t", 20) == 0;
    if (client == CONTROL_CLIENT_REDSOCKS) return strncmp(command, "NATLOOK\t", 8) == 0;
    return 0;
}
