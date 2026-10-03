#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdlib.h>
#include <dlfcn.h>
#include "check.h"
static NSMutableDictionary *values;
static unsigned writes, fail_write;
static int vc_root_stat(const char *path, struct stat *st) { int rc = lstat(path, st); if (!rc) st->st_uid = 0; return rc; }
static int vc_root_fstat(int fd, struct stat *st) { int rc = fstat(fd, st); if (!rc) st->st_uid = 0; return rc; }
static void *fake_open(const char *, int);
static void *fake_symbol(void *, const char *);
static int fake_close(void *);
#define lstat(path, st) vc_root_stat(path, st)
#define fstat(fd, st) vc_root_fstat(fd, st)
#define dlopen fake_open
#define dlsym fake_symbol
#define dlclose fake_close
#define VC_PROXY_STATE_DIRECTORY "state"
#include "../daemon/system_proxy.c"
#undef lstat
#undef fstat
#undef dlopen
#undef dlsym
#undef dlclose
static VCDynamicStoreRef fake_create(CFAllocatorRef a, CFStringRef n, void *c, void *p) { (void)a; (void)n; (void)c; (void)p; return CFRetain(values); }
static CFPropertyListRef fake_copy(VCDynamicStoreRef s, CFStringRef key) { (void)s; return CFRetain([values objectForKey:key]); }
static CFArrayRef fake_keys(VCDynamicStoreRef s, CFStringRef pattern) { (void)s; (void)pattern; return [[values allKeys] retain]; }
static Boolean fake_set(VCDynamicStoreRef s, CFStringRef key, CFPropertyListRef value) { (void)s; if (++writes == fail_write) return NO; [values setObject:value forKey:key]; return YES; }
static void *fake_open(const char *p, int f) { (void)p; (void)f; return (void *)1; }
static int fake_close(void *p) { (void)p; return 0; }
static void *fake_symbol(void *p, const char *name) {
    (void)p;
    if (!strcmp(name, "SCDynamicStoreCreate")) return fake_create;
    if (!strcmp(name, "SCDynamicStoreCopyValue")) return fake_copy;
    if (!strcmp(name, "SCDynamicStoreCopyKeyList")) return fake_keys;
    if (!strcmp(name, "SCDynamicStoreSetValue")) return fake_set;
    return NULL;
}
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    char directory[] = "/tmp/vless-host-pac.XXXXXX";
    CHECK("pac/private-directory", mkdtemp(directory) && chdir(directory) == 0);
    NSString *first = @"Setup:/Network/Service/first/Proxies", *second = @"Setup:/Network/Service/second/Proxies";
    NSDictionary *original = @{@"HTTPEnable": @1, @"HTTPProxy": @"corporate.test", @"HTTPPort": @3128, @"ProxyAutoConfigEnable": @0};
    values = [[NSMutableDictionary alloc] initWithObjectsAndKeys:original, first, original, second, nil];
    CHECK("pac/invalid-port", vc_system_proxy_enable(0) == -1 && vc_system_proxy_enable(65536) == -1);
    CHECK("pac/enable", vc_system_proxy_enable(1080) == 0);
    CHECK("pac/script-policy", [[[values objectForKey:first] objectForKey:@"ProxyAutoConfigJavaScript"] isEqual:@"function FindProxyForURL(url, host) { return \"SOCKS 127.0.0.1:1080\"; }"]);
    CHECK("pac/foreign-http-preserved-on-apply", [[[values objectForKey:first] objectForKey:@"HTTPProxy"] isEqual:@"corporate.test"]);
    struct stat st; CHECK("pac/private-backup", !stat(VC_PROXY_BACKUP_PATH, &st) && (st.st_mode & 0777) == 0600);
    CHECK("pac/disable", vc_system_proxy_disable() == 0 && [[values objectForKey:first] isEqual:original] && [[values objectForKey:second] isEqual:original]);
    CHECK("pac/backup-removed", access(VC_PROXY_BACKUP_PATH, F_OK) != 0);
    for (unsigned step = 1; step <= 2; step++) {
        writes = 0; fail_write = step;
        CHECK("pac/partial-apply-fails", vc_system_proxy_enable(1080) != 0);
        CHECK("pac/partial-apply-rollback", [[values objectForKey:first] isEqual:original] && [[values objectForKey:second] isEqual:original]);
        fail_write = 0;
    }
    CHECK("pac/re-enable", vc_system_proxy_enable(1080) == 0);
    NSMutableDictionary *changed = [[values objectForKey:first] mutableCopy];
    [changed setObject:@4138 forKey:@"HTTPPort"]; [changed setObject:@"foreign script" forKey:@"ProxyAutoConfigJavaScript"];
    [values setObject:changed forKey:first]; [changed release];
    CHECK("pac/restore-preserves-user-changes", vc_system_proxy_disable() == 0 && [[[values objectForKey:first] objectForKey:@"HTTPPort"] intValue] == 4138 && [[[values objectForKey:first] objectForKey:@"ProxyAutoConfigJavaScript"] isEqual:@"foreign script"]);
    [values setObject:original forKey:first];
    CHECK("pac/enable-before-new-service", vc_system_proxy_enable(1080) == 0);
    NSString *third = @"Setup:/Network/Service/third/Proxies"; [values setObject:original forKey:third];
    CHECK("pac/refresh-new-service", vc_system_proxy_refresh(1080) == 0 && proxy_is_ours([values objectForKey:third], 1080));
    CHECK("pac/restart-recovery", vc_system_proxy_restore_stale() == 0 && [[values objectForKey:third] isEqual:original]);
    CHECK("pac/clean-stop-is-idempotent", vc_system_proxy_disable() == 0 && vc_system_proxy_restore_stale() == 0);
    CHECK("pac/remove-test-directory", rmdir("state") == 0 && chdir("/") == 0 && rmdir(directory) == 0);
    [values release]; [pool drain]; FINISH("system proxy recovery"); return 0;
}
