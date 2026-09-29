#define _DARWIN_C_SOURCE 1
#include "legacy_dns.h"
#if !defined(__LP64__)
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifndef VC_LEGACY_DNS_PATH
#define VC_LEGACY_DNS_PATH "/var/db/vless-core/loopback-dns.plist"
#endif
#ifndef VC_LEGACY_DNS_DIRECTORY
#define VC_LEGACY_DNS_DIRECTORY "/var/db/vless-core"
#endif
typedef struct {
    void *library;
    CFTypeRef (*create)(CFAllocatorRef, CFStringRef, void *, void *);
    CFPropertyListRef (*copy)(CFTypeRef, CFStringRef);
    CFArrayRef (*keys)(CFTypeRef, CFStringRef);
    Boolean (*set)(CFTypeRef, CFStringRef, CFPropertyListRef);
    Boolean (*remove)(CFTypeRef, CFStringRef);
    CFTypeRef store;
} store_t;
static int running;

static int open_store(store_t *api) {
    memset(api, 0, sizeof(*api));
    api->library = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LOCAL | RTLD_LAZY);
    if (!api->library) return -1;
#define LOAD(field, symbol) *(void **)(&api->field) = dlsym(api->library, symbol)
    LOAD(create, "SCDynamicStoreCreate"); LOAD(copy, "SCDynamicStoreCopyValue");
    LOAD(keys, "SCDynamicStoreCopyKeyList"); LOAD(set, "SCDynamicStoreSetValue");
    LOAD(remove, "SCDynamicStoreRemoveValue");
#undef LOAD
    if (api->create && api->copy && api->keys && api->set && api->remove)
        api->store = api->create(NULL, CFSTR("vless-core iOS 5 DNS"), NULL, NULL);
    if (api->store) return 0;
    dlclose(api->library); api->library = NULL; return -1;
}
static void close_store(store_t *api) { CFRelease(api->store); dlclose(api->library); }

static int sync_directory(void) {
    int fd = open(VC_LEGACY_DNS_DIRECTORY, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    int result = fsync(fd); close(fd); return result;
}
static int save_backup(CFDictionaryRef backup) {
    CFDataRef data = CFPropertyListCreateData(NULL, backup, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
    if (!data) return -1;
    int fd = open(VC_LEGACY_DNS_PATH ".tmp", O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0600);
    int result = -1;
    if (fd >= 0) {
        CFIndex length = CFDataGetLength(data);
        if (write(fd, CFDataGetBytePtr(data), (size_t)length) == length && fsync(fd) == 0) result = 0;
        if (close(fd) != 0) result = -1;
        if (result == 0) result = rename(VC_LEGACY_DNS_PATH ".tmp", VC_LEGACY_DNS_PATH);
        if (result == 0) result = sync_directory();
        if (result != 0) (void)unlink(VC_LEGACY_DNS_PATH ".tmp");
    }
    CFRelease(data); return result;
}
static CFDictionaryRef load_backup(void) {
    int fd = open(VC_LEGACY_DNS_PATH, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return NULL;
    struct stat info;
    CFDictionaryRef result = NULL;
    if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_uid == 0 && info.st_nlink == 1 &&
        (info.st_mode & 0777) == 0600 && info.st_size > 0 && info.st_size <= 1024 * 1024) {
        unsigned char *bytes = malloc((size_t)info.st_size);
        if (bytes) {
            if (read(fd, bytes, (size_t)info.st_size) == info.st_size) {
                CFDataRef data = CFDataCreate(NULL, bytes, (CFIndex)info.st_size);
                CFPropertyListRef value = data ? CFPropertyListCreateWithData(NULL, data, kCFPropertyListImmutable, NULL, NULL) : NULL;
                if (data) CFRelease(data);
                if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) result = value;
                else if (value) CFRelease(value);
            }
            free(bytes);
        }
    }
    close(fd); if (!result) errno = EINVAL; return result;
}

static int apply_entries(store_t *api, CFDictionaryRef entries, int restore, int check) {
    CFIndex count = CFDictionaryGetCount(entries);
    if (count <= 0 || count > 64) return -1;
    const void *keys[64], *values[64];
    CFDictionaryGetKeysAndValues(entries, keys, values);
    int result = 0;
    for (CFIndex i = 0; i < count; i++) {
        if (CFGetTypeID(keys[i]) != CFStringGetTypeID() ||
            !CFStringHasPrefix(keys[i], CFSTR("Setup:/Network/Service/")) ||
            !CFStringHasSuffix(keys[i], CFSTR("/DNS")) || CFGetTypeID(values[i]) != CFDictionaryGetTypeID()) return -1;
        CFDictionaryRef original = CFDictionaryGetValue(values[i], CFSTR("Original"));
        CFDictionaryRef applied = CFDictionaryGetValue(values[i], CFSTR("Applied"));
        if (!applied || CFGetTypeID(applied) != CFDictionaryGetTypeID() ||
            (original && CFGetTypeID(original) != CFDictionaryGetTypeID())) return -1;
        CFPropertyListRef current = api->copy(api->store, keys[i]);
        int ours = current && CFEqual(current, applied);
        if (current) CFRelease(current);
        if (check) { if (!ours) result = -1; }
        else if (restore) {
            if (ours && !(original ? api->set(api->store, keys[i], original) : api->remove(api->store, keys[i]))) result = -1;
        } else if (!api->set(api->store, keys[i], applied)) result = -1;
    }
    return result;
}

int vc_legacy_dns_stop(void) {
    (void)unlink(VC_LEGACY_DNS_PATH ".tmp");
    CFDictionaryRef backup = load_backup();
    if (!backup) { if (errno == ENOENT) { running = 0; return 0; } return -1; }
    store_t api;
    int result = open_store(&api);
    if (result == 0) { result = apply_entries(&api, backup, 1, 0); close_store(&api); }
    CFRelease(backup);
    if (result == 0 && unlink(VC_LEGACY_DNS_PATH) != 0) result = -1;
    if (result == 0) { running = 0; result = sync_directory(); }
    return result;
}

int vc_legacy_dns_start(void) {
    if (vc_legacy_dns_stop() != 0) return -2;
    store_t api;
    if (open_store(&api) != 0) return -3;
    CFArrayRef services = api.keys(api.store, CFSTR("^State:/Network/Service/[^/]+/IPv4$"));
    CFMutableDictionaryRef entries = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int result = -4;
    if (services && CFGetTypeID(services) == CFArrayGetTypeID() && CFArrayGetCount(services) > 0 && CFArrayGetCount(services) <= 64 && entries) {
        for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
            CFStringRef service = CFArrayGetValueAtIndex(services, i);
            if (CFGetTypeID(service) != CFStringGetTypeID() || CFStringGetLength(service) < 11) break;
            CFStringRef id = CFStringCreateWithSubstring(NULL, service, CFRangeMake(6, CFStringGetLength(service) - 11));
            CFStringRef key = id ? CFStringCreateWithFormat(NULL, NULL, CFSTR("Setup:%@/DNS"), id) : NULL;
            if (id) CFRelease(id);
            if (!key) break;
            CFDictionaryRef original = (CFDictionaryRef)api.copy(api.store, key);
            if (original && CFGetTypeID(original) != CFDictionaryGetTypeID()) { CFRelease(original); CFRelease(key); break; }
            CFMutableDictionaryRef applied = original ? CFDictionaryCreateMutableCopy(NULL, 0, original) :
                CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFStringRef resolver = CFSTR("1.1.1.1");
            CFArrayRef addresses = CFArrayCreate(NULL, (const void **)&resolver, 1, &kCFTypeArrayCallBacks);
            CFMutableDictionaryRef entry = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            if (applied && addresses && entry) {
                CFDictionarySetValue(applied, CFSTR("ServerAddresses"), addresses);
                CFDictionarySetValue(entry, CFSTR("Applied"), applied);
                if (original) CFDictionarySetValue(entry, CFSTR("Original"), original);
                CFDictionarySetValue(entries, key, entry);
            }
            if (original) CFRelease(original); if (applied) CFRelease(applied);
            if (addresses) CFRelease(addresses); if (entry) CFRelease(entry); CFRelease(key);
        }
        if (CFDictionaryGetCount(entries) == CFArrayGetCount(services)) {
            result = save_backup(entries) == 0 ? 0 : -5;
            if (result == 0 && apply_entries(&api, entries, 0, 0) != 0) result = -6;
        }
    }
    if (entries) CFRelease(entries); if (services) CFRelease(services); close_store(&api);
    if (result != 0) (void)vc_legacy_dns_stop();
    else running = 1;
    return result;
}

int vc_legacy_dns_healthy(void) {
    if (!running) return 1;
    CFDictionaryRef backup = load_backup();
    if (!backup) return 0;
    store_t api;
    int result = open_store(&api);
    if (result == 0) { result = apply_entries(&api, backup, 0, 1); close_store(&api); }
    CFRelease(backup); return result == 0;
}
#else
int vc_legacy_dns_start(void) { return -1; }
int vc_legacy_dns_stop(void) { return 0; }
int vc_legacy_dns_healthy(void) { return 1; }
#endif
