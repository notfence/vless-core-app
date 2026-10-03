#ifndef VC_CONTROL_AUTH_H
#define VC_CONTROL_AUTH_H
#include <sys/stat.h>
typedef enum {
    CONTROL_CLIENT_UNAUTHORIZED = 0,
    CONTROL_CLIENT_APP = 1,
    CONTROL_CLIENT_BOOTSTRAP = 2,
    CONTROL_CLIENT_CORE = 3,
    CONTROL_CLIENT_REDSOCKS = 4,
} control_client_t;
typedef struct {
    char *(*resolve)(const char *, char *);
    int (*file_info)(const char *, struct stat *);
} VCControlAuthOperations;
int VCExecutablePathMatches(const char *actual, const char *expected, int *trust_error, const VCControlAuthOperations *operations);
int VCControlCommandAllowed(control_client_t client, const char *command);
#endif
