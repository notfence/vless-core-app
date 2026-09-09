#include "system_proxy.h"

#if defined(__LP64__)

#include <CoreFoundation/CoreFoundation.h>

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define VC_PROXY_STATE_DIRECTORY "/var/db/vless-core"
#define VC_PROXY_BACKUP_PATH VC_PROXY_STATE_DIRECTORY "/system-proxy-backup.plist"
#define VC_PROXY_BACKUP_TEMP_PATH VC_PROXY_STATE_DIRECTORY "/system-proxy-backup.plist.tmp"
#define VC_PROXY_BACKUP_CORRUPT_PATH VC_PROXY_STATE_DIRECTORY "/system-proxy-backup.corrupt.plist"
#define VC_PROXY_BACKUP_MAX_SIZE (1024U * 1024U)

typedef const void *VCDynamicStoreRef;

typedef struct {
    void *handle;
    VCDynamicStoreRef (*store_create)(CFAllocatorRef, CFStringRef, void *, void *);
    CFPropertyListRef (*store_copy_value)(VCDynamicStoreRef, CFStringRef);
    CFArrayRef (*store_copy_key_list)(VCDynamicStoreRef, CFStringRef);
    Boolean (*store_set_value)(VCDynamicStoreRef, CFStringRef, CFPropertyListRef);
} VCSystemConfigurationAPI;

static CFStringRef const kProxyOwnerKey = CFSTR("VlessCoreProxyOwner");
static CFStringRef const kProxyOriginalKey = CFSTR("Original");
static CFStringRef const kProxyAppliedKey = CFSTR("Applied");
static CFStringRef const kProxyServicePattern =
    CFSTR("^Setup:/Network/Service/[^/]+/Proxies$");

static int load_symbol(void *handle, const char *name, void **value) {
    *value = dlsym(handle, name);
    return *value ? 0 : -1;
}

static int load_system_configuration(VCSystemConfigurationAPI *api) {
    memset(api, 0, sizeof(*api));
    api->handle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration",
                         RTLD_LAZY | RTLD_LOCAL);
    if (!api->handle) return -1;

#define VC_LOAD_FUNCTION(field, symbol) \
    do { \
        if (load_symbol(api->handle, symbol, (void **)&api->field) != 0) goto fail; \
    } while (0)

    VC_LOAD_FUNCTION(store_create, "SCDynamicStoreCreate");
    VC_LOAD_FUNCTION(store_copy_value, "SCDynamicStoreCopyValue");
    VC_LOAD_FUNCTION(store_copy_key_list, "SCDynamicStoreCopyKeyList");
    VC_LOAD_FUNCTION(store_set_value, "SCDynamicStoreSetValue");
    return 0;

fail:
    dlclose(api->handle);
    memset(api, 0, sizeof(*api));
    return -1;
#undef VC_LOAD_FUNCTION
}

static void unload_system_configuration(VCSystemConfigurationAPI *api) {
    if (api->handle) dlclose(api->handle);
    memset(api, 0, sizeof(*api));
}

static int ensure_state_directory(void) {
    struct stat st;
    if (lstat(VC_PROXY_STATE_DIRECTORY, &st) != 0) {
        if (errno != ENOENT || mkdir(VC_PROXY_STATE_DIRECTORY, 0700) != 0) return -1;
        if (lstat(VC_PROXY_STATE_DIRECTORY, &st) != 0) return -1;
    }
    if (!S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != 0) return -1;
    if ((st.st_mode & 0777) != 0700 && chmod(VC_PROXY_STATE_DIRECTORY, 0700) != 0) return -1;
    return 0;
}

static int sync_state_directory(void) {
    int fd = open(VC_PROXY_STATE_DIRECTORY, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    struct stat st;
    int result = fstat(fd, &st) == 0 && S_ISDIR(st.st_mode) && fsync(fd) == 0 ? 0 : -1;
    close(fd);
    return result;
}

static int remove_state_file(const char *path) {
    if (unlink(path) != 0) return errno == ENOENT ? 0 : -1;
    return sync_state_directory();
}

static int write_all(int fd, const uint8_t *bytes, size_t length) {
    size_t offset = 0;
    while (offset < length) {
        ssize_t count = write(fd, bytes + offset, length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return -1;
        offset += (size_t)count;
    }
    return 0;
}

static int write_backup(CFDictionaryRef backup) {
    if (ensure_state_directory() != 0) return -1;

    CFErrorRef error = NULL;
    CFDataRef data = CFPropertyListCreateData(kCFAllocatorDefault,
                                               backup,
                                               kCFPropertyListBinaryFormat_v1_0,
                                               0,
                                               &error);
    if (error) CFRelease(error);
    if (!data || CFDataGetLength(data) <= 0 ||
        (size_t)CFDataGetLength(data) > VC_PROXY_BACKUP_MAX_SIZE) {
        if (data) CFRelease(data);
        return -1;
    }

    (void)unlink(VC_PROXY_BACKUP_TEMP_PATH);
    int fd = open(VC_PROXY_BACKUP_TEMP_PATH,
                  O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                  0600);
    if (fd < 0) {
        CFRelease(data);
        return -1;
    }
    int result = write_all(fd,
                           CFDataGetBytePtr(data),
                           (size_t)CFDataGetLength(data));
    if (result == 0 && fsync(fd) != 0) result = -1;
    if (close(fd) != 0) result = -1;
    CFRelease(data);

    if (result == 0 && rename(VC_PROXY_BACKUP_TEMP_PATH, VC_PROXY_BACKUP_PATH) != 0) {
        result = -1;
    }
    if (result == 0 && sync_state_directory() != 0) result = -1;
    if (result != 0) (void)unlink(VC_PROXY_BACKUP_TEMP_PATH);
    return result;
}

static CFDictionaryRef copy_backup(void) {
    int fd = open(VC_PROXY_BACKUP_PATH, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return NULL;

    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 ||
        st.st_size <= 0 || (uint64_t)st.st_size > VC_PROXY_BACKUP_MAX_SIZE) {
        close(fd);
        return NULL;
    }

    size_t length = (size_t)st.st_size;
    uint8_t *bytes = malloc(length);
    if (!bytes) {
        close(fd);
        return NULL;
    }
    size_t offset = 0;
    while (offset < length) {
        ssize_t count = read(fd, bytes + offset, length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (size_t)count;
    }
    close(fd);
    if (offset != length) {
        free(bytes);
        return NULL;
    }

    CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)length);
    memset(bytes, 0, length);
    free(bytes);
    if (!data) return NULL;

    CFErrorRef error = NULL;
    CFPropertyListRef property = CFPropertyListCreateWithData(kCFAllocatorDefault,
                                                               data,
                                                               kCFPropertyListImmutable,
                                                               NULL,
                                                               &error);
    CFRelease(data);
    if (error) CFRelease(error);
    if (!property || CFGetTypeID(property) != CFDictionaryGetTypeID()) {
        if (property) CFRelease(property);
        return NULL;
    }
    return (CFDictionaryRef)property;
}

static int backup_exists(void) {
    struct stat st;
    return lstat(VC_PROXY_BACKUP_PATH, &st) == 0 &&
           S_ISREG(st.st_mode) && !S_ISLNK(st.st_mode);
}

static int dictionary_int(CFDictionaryRef dictionary, CFStringRef key, int *value) {
    CFNumberRef number = dictionary ? CFDictionaryGetValue(dictionary, key) : NULL;
    return number && CFGetTypeID(number) == CFNumberGetTypeID() &&
           CFNumberGetValue(number, kCFNumberIntType, value);
}

static CFStringRef create_pac_script(int socks_port) {
    return CFStringCreateWithFormat(
        kCFAllocatorDefault,
        NULL,
        CFSTR("function FindProxyForURL(url, host) { return \"SOCKS 127.0.0.1:%d\"; }"),
        socks_port);
}

static int proxy_is_ours(CFDictionaryRef proxy, int socks_port) {
    if (!proxy || CFGetTypeID(proxy) != CFDictionaryGetTypeID()) return 0;
    if (CFDictionaryGetValue(proxy, kProxyOwnerKey) == kCFBooleanTrue) return 1;

    int enabled = 0;
    CFStringRef current_script = CFDictionaryGetValue(proxy, CFSTR("ProxyAutoConfigJavaScript"));
    CFStringRef expected_script = create_pac_script(socks_port);
    int matches = dictionary_int(proxy, CFSTR("ProxyAutoConfigEnable"), &enabled) && enabled != 0 &&
                  current_script && CFGetTypeID(current_script) == CFStringGetTypeID() &&
                  expected_script &&
                  CFStringCompare(current_script, expected_script, 0) == kCFCompareEqualTo;
    if (expected_script) CFRelease(expected_script);
    return matches;
}

static CFDictionaryRef create_backup(CFDictionaryRef configurations, int port) {
    CFMutableDictionaryRef backup = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                               0,
                                                               &kCFTypeDictionaryKeyCallBacks,
                                                               &kCFTypeDictionaryValueCallBacks);
    if (!backup) return NULL;

    int version = 4;
    CFNumberRef version_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &version);
    CFNumberRef port_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &port);
    if (!version_number || !port_number) {
        if (version_number) CFRelease(version_number);
        if (port_number) CFRelease(port_number);
        CFRelease(backup);
        return NULL;
    }
    CFDictionarySetValue(backup, CFSTR("Version"), version_number);
    CFDictionarySetValue(backup, CFSTR("AppliedPort"), port_number);
    CFDictionarySetValue(backup, CFSTR("Configurations"), configurations);
    CFRelease(version_number);
    CFRelease(port_number);
    return backup;
}

static int set_pac_values(CFMutableDictionaryRef proxy, int socks_port) {
    int enabled = 1;
    CFNumberRef enabled_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &enabled);
    CFStringRef script = create_pac_script(socks_port);
    if (!enabled_number || !script) {
        if (enabled_number) CFRelease(enabled_number);
        if (script) CFRelease(script);
        return -1;
    }

    CFDictionarySetValue(proxy, CFSTR("ProxyAutoConfigEnable"), enabled_number);
    CFDictionarySetValue(proxy, CFSTR("ProxyAutoConfigJavaScript"), script);
    CFDictionarySetValue(proxy, kProxyOwnerKey, kCFBooleanTrue);
    CFRelease(enabled_number);
    CFRelease(script);
    return 0;
}

static CFMutableDictionaryRef create_applied_proxy(CFDictionaryRef original, int socks_port) {
    if (!original || CFGetTypeID(original) != CFDictionaryGetTypeID()) return NULL;
    CFMutableDictionaryRef applied =
        CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, original);
    if (!applied || set_pac_values(applied, socks_port) != 0) {
        if (applied) CFRelease(applied);
        return NULL;
    }
    return applied;
}

static CFDictionaryRef create_configuration_entry(CFDictionaryRef original,
                                                   CFDictionaryRef applied) {
    if (!original || !applied ||
        CFGetTypeID(original) != CFDictionaryGetTypeID() ||
        CFGetTypeID(applied) != CFDictionaryGetTypeID()) {
        return NULL;
    }
    const void *keys[] = { kProxyOriginalKey, kProxyAppliedKey };
    const void *values[] = { original, applied };
    return CFDictionaryCreate(kCFAllocatorDefault,
                              keys,
                              values,
                              2,
                              &kCFTypeDictionaryKeyCallBacks,
                              &kCFTypeDictionaryValueCallBacks);
}

static int optional_values_equal(const void *left, const void *right) {
    if (!left || !right) return left == right;
    return CFEqual(left, right);
}

static int entry_dictionaries(CFDictionaryRef entry,
                              CFDictionaryRef *original,
                              CFDictionaryRef *applied) {
    if (!entry || CFGetTypeID(entry) != CFDictionaryGetTypeID()) return -1;
    CFDictionaryRef saved_original = CFDictionaryGetValue(entry, kProxyOriginalKey);
    CFDictionaryRef saved_applied = CFDictionaryGetValue(entry, kProxyAppliedKey);
    if (!saved_original || !saved_applied ||
        CFGetTypeID(saved_original) != CFDictionaryGetTypeID() ||
        CFGetTypeID(saved_applied) != CFDictionaryGetTypeID()) {
        return -1;
    }
    *original = saved_original;
    *applied = saved_applied;
    return 0;
}

static int applied_changes_match(CFDictionaryRef current,
                                 CFDictionaryRef original,
                                 CFDictionaryRef applied) {
    CFIndex count = CFDictionaryGetCount(applied);
    const void **keys = count > 0 ? calloc((size_t)count, sizeof(*keys)) : NULL;
    const void **values = count > 0 ? calloc((size_t)count, sizeof(*values)) : NULL;
    if (count > 0 && (!keys || !values)) {
        free(keys);
        free(values);
        return -1;
    }
    CFDictionaryGetKeysAndValues(applied, keys, values);
    for (CFIndex index = 0; index < count; index++) {
        const void *original_value = CFDictionaryGetValue(original, keys[index]);
        if (!optional_values_equal(original_value, values[index]) &&
            !optional_values_equal(CFDictionaryGetValue(current, keys[index]), values[index])) {
            free(keys);
            free(values);
            return 0;
        }
    }
    free(keys);
    free(values);

    count = CFDictionaryGetCount(original);
    keys = count > 0 ? calloc((size_t)count, sizeof(*keys)) : NULL;
    values = count > 0 ? calloc((size_t)count, sizeof(*values)) : NULL;
    if (count > 0 && (!keys || !values)) {
        free(keys);
        free(values);
        return -1;
    }
    CFDictionaryGetKeysAndValues(original, keys, values);
    for (CFIndex index = 0; index < count; index++) {
        const void *applied_value = CFDictionaryGetValue(applied, keys[index]);
        if (!applied_value && CFDictionaryGetValue(current, keys[index])) {
            free(keys);
            free(values);
            return 0;
        }
    }
    free(keys);
    free(values);
    return 1;
}

static CFMutableDictionaryRef create_three_way_restored_proxy(CFDictionaryRef current,
                                                               CFDictionaryRef original,
                                                               CFDictionaryRef applied) {
    CFMutableDictionaryRef restored =
        CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, current);
    if (!restored) return NULL;

    CFIndex count = CFDictionaryGetCount(applied);
    const void **keys = count > 0 ? calloc((size_t)count, sizeof(*keys)) : NULL;
    const void **values = count > 0 ? calloc((size_t)count, sizeof(*values)) : NULL;
    if (count > 0 && (!keys || !values)) goto fail;
    CFDictionaryGetKeysAndValues(applied, keys, values);
    for (CFIndex index = 0; index < count; index++) {
        const void *original_value = CFDictionaryGetValue(original, keys[index]);
        const void *current_value = CFDictionaryGetValue(current, keys[index]);
        if (!optional_values_equal(original_value, values[index]) &&
            optional_values_equal(current_value, values[index])) {
            if (original_value) {
                CFDictionarySetValue(restored, keys[index], original_value);
            } else {
                CFDictionaryRemoveValue(restored, keys[index]);
            }
        }
    }
    free(keys);
    free(values);
    keys = NULL;
    values = NULL;

    count = CFDictionaryGetCount(original);
    keys = count > 0 ? calloc((size_t)count, sizeof(*keys)) : NULL;
    values = count > 0 ? calloc((size_t)count, sizeof(*values)) : NULL;
    if (count > 0 && (!keys || !values)) goto fail;
    CFDictionaryGetKeysAndValues(original, keys, values);
    for (CFIndex index = 0; index < count; index++) {
        if (!CFDictionaryGetValue(applied, keys[index]) &&
            !CFDictionaryGetValue(current, keys[index])) {
            CFDictionarySetValue(restored, keys[index], values[index]);
        }
    }
    free(keys);
    free(values);
    return restored;

fail:
    free(keys);
    free(values);
    CFRelease(restored);
    return NULL;
}

int vc_system_proxy_disable(void) {
    if (!backup_exists()) return 0;

    CFDictionaryRef backup = copy_backup();
    int version = 0;
    int applied_port = 0;
    if (!backup || !dictionary_int(backup, CFSTR("Version"), &version) ||
        (version != 3 && version != 4) ||
        !dictionary_int(backup, CFSTR("AppliedPort"), &applied_port) ||
        applied_port <= 0 || applied_port > 65535) {
        if (backup) CFRelease(backup);
        return -2;
    }
    CFDictionaryRef configurations = CFDictionaryGetValue(backup, CFSTR("Configurations"));
    if (!configurations || CFGetTypeID(configurations) != CFDictionaryGetTypeID()) {
        CFRelease(backup);
        return -1;
    }

    VCSystemConfigurationAPI api;
    if (load_system_configuration(&api) != 0) {
        CFRelease(backup);
        return -1;
    }
    VCDynamicStoreRef store = api.store_create(kCFAllocatorDefault,
                                                CFSTR("vless-core proxy restore"),
                                                NULL,
                                                NULL);
    if (!store) {
        unload_system_configuration(&api);
        CFRelease(backup);
        return -1;
    }

    int result = 0;
    CFIndex count = CFDictionaryGetCount(configurations);
    const void **keys = count > 0 ? calloc((size_t)count, sizeof(*keys)) : NULL;
    const void **values = count > 0 ? calloc((size_t)count, sizeof(*values)) : NULL;
    if (count > 0 && (!keys || !values)) {
        result = -1;
    } else {
        CFDictionaryGetKeysAndValues(configurations, keys, values);
        for (CFIndex index = 0; index < count; index++) {
            CFStringRef key = (CFStringRef)keys[index];
            CFDictionaryRef original = NULL;
            CFDictionaryRef applied = NULL;
            if (version == 3) {
                original = (CFDictionaryRef)values[index];
                if (!original || CFGetTypeID(original) != CFDictionaryGetTypeID()) {
                    result = -1;
                    break;
                }
            } else if (entry_dictionaries((CFDictionaryRef)values[index],
                                          &original,
                                          &applied) != 0) {
                result = -1;
                break;
            }
            CFDictionaryRef current = (CFDictionaryRef)api.store_copy_value(store, key);
            if (current && CFGetTypeID(current) != CFDictionaryGetTypeID()) {
                CFRelease(current);
                current = NULL;
            }
            if (current && version == 3 && proxy_is_ours(current, applied_port)) {
                if (!api.store_set_value(store, key, original)) result = -1;
            } else if (current && version == 4) {
                CFMutableDictionaryRef restored =
                    create_three_way_restored_proxy(current, original, applied);
                if (!restored) {
                    result = -1;
                } else if (!CFEqual(current, restored) &&
                           !api.store_set_value(store, key, restored)) {
                    result = -1;
                }
                if (restored) CFRelease(restored);
            }
            if (current) CFRelease(current);
            if (result != 0) break;
        }
    }
    free(keys);
    free(values);
    if (count <= 0) result = -1;

    CFRelease(store);
    unload_system_configuration(&api);
    CFRelease(backup);
    if (result == 0 && remove_state_file(VC_PROXY_BACKUP_PATH) != 0) result = -1;
    return result;
}

int vc_system_proxy_enable(int socks_port) {
    if (socks_port <= 0 || socks_port > 65535) return -1;
    if (backup_exists() && vc_system_proxy_disable() != 0) return -1;

    VCSystemConfigurationAPI api;
    if (load_system_configuration(&api) != 0) return -1;
    VCDynamicStoreRef store = api.store_create(kCFAllocatorDefault,
                                                CFSTR("vless-core proxy enable"),
                                                NULL,
                                                NULL);
    if (!store) {
        unload_system_configuration(&api);
        return -1;
    }

    CFArrayRef service_keys = api.store_copy_key_list(store, kProxyServicePattern);
    int result = 0;
    if (!service_keys || CFGetTypeID(service_keys) != CFArrayGetTypeID() ||
        CFArrayGetCount(service_keys) <= 0) {
        result = -1;
    }

    CFMutableDictionaryRef configurations = result == 0
        ? CFDictionaryCreateMutable(kCFAllocatorDefault,
                                    0,
                                    &kCFTypeDictionaryKeyCallBacks,
                                    &kCFTypeDictionaryValueCallBacks)
        : NULL;
    if (result == 0 && !configurations) result = -1;
    if (result == 0) {
        CFIndex count = CFArrayGetCount(service_keys);
        for (CFIndex index = 0; index < count; index++) {
            CFStringRef key = CFArrayGetValueAtIndex(service_keys, index);
            CFDictionaryRef current = (CFDictionaryRef)api.store_copy_value(store, key);
            if (!current || CFGetTypeID(current) != CFDictionaryGetTypeID()) {
                if (current) CFRelease(current);
                result = -1;
                break;
            }
            CFMutableDictionaryRef applied = create_applied_proxy(current, socks_port);
            CFDictionaryRef entry = create_configuration_entry(current, applied);
            if (!applied || !entry) {
                if (entry) CFRelease(entry);
                if (applied) CFRelease(applied);
                CFRelease(current);
                result = -1;
                break;
            }
            CFDictionarySetValue(configurations, key, entry);
            CFRelease(entry);
            CFRelease(applied);
            CFRelease(current);
        }
    }

    CFDictionaryRef backup = result == 0 ? create_backup(configurations, socks_port) : NULL;
    if (!backup || write_backup(backup) != 0) result = -1;

    if (result == 0) {
        CFIndex count = CFArrayGetCount(service_keys);
        for (CFIndex index = 0; index < count; index++) {
            CFStringRef key = CFArrayGetValueAtIndex(service_keys, index);
            CFDictionaryRef entry = CFDictionaryGetValue(configurations, key);
            CFDictionaryRef original = NULL;
            CFDictionaryRef applied = NULL;
            if (entry_dictionaries(entry, &original, &applied) != 0 ||
                !api.store_set_value(store, key, applied)) {
                result = -1;
            }
            (void)original;
            if (result != 0) break;
        }
    }

    if (backup) CFRelease(backup);
    if (configurations) CFRelease(configurations);
    if (service_keys) CFRelease(service_keys);
    CFRelease(store);
    unload_system_configuration(&api);

    if (result != 0 && backup_exists()) (void)vc_system_proxy_disable();
    return result;
}

int vc_system_proxy_refresh(int socks_port) {
    if (socks_port <= 0 || socks_port > 65535 || !backup_exists()) return -1;

    CFDictionaryRef backup = copy_backup();
    int version = 0;
    int applied_port = 0;
    if (!backup || !dictionary_int(backup, CFSTR("Version"), &version) || version != 4 ||
        !dictionary_int(backup, CFSTR("AppliedPort"), &applied_port) ||
        applied_port != socks_port) {
        if (backup) CFRelease(backup);
        return -1;
    }
    CFDictionaryRef configurations = CFDictionaryGetValue(backup, CFSTR("Configurations"));
    if (!configurations || CFGetTypeID(configurations) != CFDictionaryGetTypeID()) {
        CFRelease(backup);
        return -1;
    }

    VCSystemConfigurationAPI api;
    if (load_system_configuration(&api) != 0) {
        CFRelease(backup);
        return -1;
    }
    VCDynamicStoreRef store = api.store_create(kCFAllocatorDefault,
                                                CFSTR("vless-core proxy refresh"),
                                                NULL,
                                                NULL);
    if (!store) {
        unload_system_configuration(&api);
        CFRelease(backup);
        return -1;
    }

    CFArrayRef service_keys = api.store_copy_key_list(store, kProxyServicePattern);
    CFMutableDictionaryRef updated =
        CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, configurations);
    CFMutableDictionaryRef pending =
        CFDictionaryCreateMutable(kCFAllocatorDefault,
                                  0,
                                  &kCFTypeDictionaryKeyCallBacks,
                                  &kCFTypeDictionaryValueCallBacks);
    int result = 0;
    if (!service_keys || CFGetTypeID(service_keys) != CFArrayGetTypeID() ||
        CFArrayGetCount(service_keys) <= 0 || !updated || !pending) {
        result = -1;
    }

    if (result == 0) {
        CFIndex count = CFArrayGetCount(service_keys);
        for (CFIndex index = 0; index < count; index++) {
            CFStringRef key = CFArrayGetValueAtIndex(service_keys, index);
            CFDictionaryRef current = (CFDictionaryRef)api.store_copy_value(store, key);
            if (!current) continue;
            if (CFGetTypeID(current) != CFDictionaryGetTypeID()) {
                CFRelease(current);
                result = -1;
                break;
            }

            CFDictionaryRef entry = CFDictionaryGetValue(configurations, key);
            CFMutableDictionaryRef baseline = NULL;
            if (entry) {
                CFDictionaryRef original = NULL;
                CFDictionaryRef applied = NULL;
                int matches = entry_dictionaries(entry, &original, &applied) == 0
                    ? applied_changes_match(current, original, applied)
                    : -1;
                if (matches < 0) {
                    CFRelease(current);
                    result = -1;
                    break;
                }
                if (matches > 0) {
                    CFRelease(current);
                    continue;
                }
                baseline = create_three_way_restored_proxy(current, original, applied);
            } else {
                baseline = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, current);
            }

            CFMutableDictionaryRef applied = create_applied_proxy(baseline, socks_port);
            CFDictionaryRef new_entry = create_configuration_entry(baseline, applied);
            if (!baseline || !applied || !new_entry) {
                if (new_entry) CFRelease(new_entry);
                if (applied) CFRelease(applied);
                if (baseline) CFRelease(baseline);
                CFRelease(current);
                result = -1;
                break;
            }
            CFDictionarySetValue(updated, key, new_entry);
            CFDictionarySetValue(pending, key, applied);
            CFRelease(new_entry);
            CFRelease(applied);
            CFRelease(baseline);
            CFRelease(current);
        }
    }

    if (result == 0 && CFDictionaryGetCount(pending) > 0) {
        CFDictionaryRef updated_backup = create_backup(updated, socks_port);
        if (!updated_backup || write_backup(updated_backup) != 0) result = -1;
        if (updated_backup) CFRelease(updated_backup);
    }

    if (result == 0 && CFDictionaryGetCount(pending) > 0) {
        CFIndex count = CFDictionaryGetCount(pending);
        const void **keys = calloc((size_t)count, sizeof(*keys));
        const void **values = calloc((size_t)count, sizeof(*values));
        if (!keys || !values) {
            result = -1;
        } else {
            CFDictionaryGetKeysAndValues(pending, keys, values);
            for (CFIndex index = 0; index < count; index++) {
                if (!api.store_set_value(store,
                                         (CFStringRef)keys[index],
                                         (CFDictionaryRef)values[index])) {
                    result = -1;
                    break;
                }
            }
        }
        free(keys);
        free(values);
    }

    if (pending) CFRelease(pending);
    if (updated) CFRelease(updated);
    if (service_keys) CFRelease(service_keys);
    CFRelease(store);
    unload_system_configuration(&api);
    CFRelease(backup);
    return result;
}

static int proxy_has_vless_signature(CFDictionaryRef proxy) {
    if (!proxy || CFGetTypeID(proxy) != CFDictionaryGetTypeID()) return 0;
    if (CFDictionaryGetValue(proxy, kProxyOwnerKey) == kCFBooleanTrue) return 1;
    CFStringRef script = CFDictionaryGetValue(proxy, CFSTR("ProxyAutoConfigJavaScript"));
    return script && CFGetTypeID(script) == CFStringGetTypeID() &&
           CFStringFind(script, CFSTR("SOCKS 127.0.0.1:"), 0).location != kCFNotFound;
}

static int system_has_vless_proxy(void) {
    VCSystemConfigurationAPI api;
    if (load_system_configuration(&api) != 0) return -1;
    VCDynamicStoreRef store = api.store_create(kCFAllocatorDefault,
                                                CFSTR("vless-core proxy recovery"),
                                                NULL,
                                                NULL);
    if (!store) {
        unload_system_configuration(&api);
        return -1;
    }
    CFArrayRef service_keys = api.store_copy_key_list(store, kProxyServicePattern);
    int result = service_keys && CFGetTypeID(service_keys) == CFArrayGetTypeID() ? 0 : -1;
    if (result == 0) {
        CFIndex count = CFArrayGetCount(service_keys);
        for (CFIndex index = 0; index < count; index++) {
            CFStringRef key = CFArrayGetValueAtIndex(service_keys, index);
            CFDictionaryRef current = (CFDictionaryRef)api.store_copy_value(store, key);
            if (proxy_has_vless_signature(current)) result = 1;
            if (current) CFRelease(current);
            if (result != 0) break;
        }
    }
    if (service_keys) CFRelease(service_keys);
    CFRelease(store);
    unload_system_configuration(&api);
    return result;
}

static int quarantine_corrupt_backup(void) {
    (void)unlink(VC_PROXY_BACKUP_CORRUPT_PATH);
    if (rename(VC_PROXY_BACKUP_PATH, VC_PROXY_BACKUP_CORRUPT_PATH) != 0) return -1;
    return sync_state_directory();
}

int vc_system_proxy_restore_stale(void) {
    if (ensure_state_directory() != 0) return -1;
    if (remove_state_file(VC_PROXY_BACKUP_TEMP_PATH) != 0) return -1;
    if (!backup_exists()) return 0;

    int result = vc_system_proxy_disable();
    if (result != -2) return result;
    int active = system_has_vless_proxy();
    if (active != 0) return -1;
    return quarantine_corrupt_backup();
}

int vc_system_proxy_status(void) {
    return system_has_vless_proxy();
}

#else

int vc_system_proxy_enable(int socks_port) {
    (void)socks_port;
    return 0;
}

int vc_system_proxy_disable(void) {
    return 0;
}

int vc_system_proxy_refresh(int socks_port) {
    (void)socks_port;
    return 0;
}

int vc_system_proxy_restore_stale(void) {
    return 0;
}

int vc_system_proxy_status(void) {
    return -2;
}

#endif
