#define _POSIX_C_SOURCE 200809L

#include "vpnicon_statusbar.h"

#include <ctype.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

typedef void *objc_id_t;
typedef void *objc_sel_t;

typedef objc_id_t (*objc_get_class_fn)(const char *name);
typedef objc_sel_t (*sel_register_name_fn)(const char *name);

static const char *kSystemVersionPath = "/System/Library/CoreServices/SystemVersion.plist";
static const char *kObjCRuntimePath = "/usr/lib/libobjc.A.dylib";
static const char *kUIKitPath = "/System/Library/Frameworks/UIKit.framework/UIKit";

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static void *g_objc_handle = NULL;
static void *g_uikit_handle = NULL;
static void *g_msg_send = NULL;
static objc_get_class_fn g_objc_get_class = NULL;
static sel_register_name_fn g_sel_register_name = NULL;
static objc_id_t g_status_bar_server = NULL;
static objc_sel_t g_add_item_sel = NULL;
static objc_sel_t g_remove_item_sel = NULL;
static int g_ios_major = -1;
static int g_vpn_item_type = -1;
static int g_ready = 0;
static int g_unsupported = 0;
static int g_published = 0;
static char g_last_error[192];

static void set_error_locked(const char *message) {
    if (!message) message = "unknown error";
    snprintf(g_last_error, sizeof(g_last_error), "%s", message);
}

static int read_ios_major_version(void) {
    int fd = open(kSystemVersionPath, O_RDONLY);
    if (fd < 0) return -1;

    char data[16385];
    size_t used = 0;
    while (used < sizeof(data) - 1) {
        ssize_t n = read(fd, data + used, sizeof(data) - 1 - used);
        if (n > 0) {
            used += (size_t)n;
            continue;
        }
        break;
    }
    close(fd);
    data[used] = '\0';

    const char *key = strstr(data, "<key>ProductVersion</key>");
    if (!key) key = strstr(data, "ProductVersion");
    if (!key) return -1;

    const char *value = strstr(key, "<string>");
    if (value) value += strlen("<string>");
    else value = key + strlen("ProductVersion");

    const char *end = data + used;
    while (value < end && !isdigit((unsigned char)*value)) value++;
    if (value >= end) return -1;

    long major = strtol(value, NULL, 10);
    if (major <= 0 || major > 100) return -1;
    return (int)major;
}

static int load_function(void *handle, const char *name, void *target, size_t target_size) {
    void *symbol = dlsym(handle, name);
    if (!symbol || target_size != sizeof(symbol)) return -1;
    memcpy(target, &symbol, target_size);
    return 0;
}

static objc_id_t send_id(objc_id_t receiver, objc_sel_t selector) {
    objc_id_t (*fn)(objc_id_t, objc_sel_t) = NULL;
    memcpy(&fn, &g_msg_send, sizeof(fn));
    return fn(receiver, selector);
}

static objc_id_t send_id_int(objc_id_t receiver, objc_sel_t selector, int value) {
    objc_id_t (*fn)(objc_id_t, objc_sel_t, int) = NULL;
    memcpy(&fn, &g_msg_send, sizeof(fn));
    return fn(receiver, selector, value);
}

static objc_id_t send_id_int_int(objc_id_t receiver, objc_sel_t selector, int a, int b) {
    objc_id_t (*fn)(objc_id_t, objc_sel_t, int, int) = NULL;
    memcpy(&fn, &g_msg_send, sizeof(fn));
    return fn(receiver, selector, a, b);
}

static int send_bool_sel(objc_id_t receiver, objc_sel_t selector, objc_sel_t value) {
    signed char (*fn)(objc_id_t, objc_sel_t, objc_sel_t) = NULL;
    memcpy(&fn, &g_msg_send, sizeof(fn));
    return fn(receiver, selector, value) ? 1 : 0;
}

static int send_bool_int(objc_id_t receiver, objc_sel_t selector, int value) {
    signed char (*fn)(objc_id_t, objc_sel_t, int) = NULL;
    memcpy(&fn, &g_msg_send, sizeof(fn));
    return fn(receiver, selector, value) ? 1 : 0;
}

static void send_void(objc_id_t receiver, objc_sel_t selector) {
    void (*fn)(objc_id_t, objc_sel_t) = NULL;
    memcpy(&fn, &g_msg_send, sizeof(fn));
    fn(receiver, selector);
}

static void send_void_int(objc_id_t receiver, objc_sel_t selector, int value) {
    void (*fn)(objc_id_t, objc_sel_t, int) = NULL;
    memcpy(&fn, &g_msg_send, sizeof(fn));
    fn(receiver, selector, value);
}

static const char *send_cstring(objc_id_t receiver, objc_sel_t selector) {
    const char *(*fn)(objc_id_t, objc_sel_t) = NULL;
    memcpy(&fn, &g_msg_send, sizeof(fn));
    return fn(receiver, selector);
}

static objc_id_t create_autorelease_pool(void) {
    objc_id_t pool_class = g_objc_get_class("NSAutoreleasePool");
    if (!pool_class) return NULL;
    objc_sel_t alloc_sel = g_sel_register_name("alloc");
    objc_sel_t init_sel = g_sel_register_name("init");
    objc_id_t pool = send_id(pool_class, alloc_sel);
    return pool ? send_id(pool, init_sel) : NULL;
}

static void drain_autorelease_pool(objc_id_t pool) {
    if (!pool) return;
    send_void(pool, g_sel_register_name("drain"));
}

static int find_vpn_item_type_locked(objc_id_t item_class) {
    objc_sel_t responds_sel = g_sel_register_name("respondsToSelector:");
    objc_sel_t item_with_idiom_sel = g_sel_register_name("itemWithType:idiom:");
    objc_sel_t item_sel = g_sel_register_name("itemWithType:");
    objc_sel_t valid_sel = g_sel_register_name("typeIsValid:");
    objc_sel_t indicator_sel = g_sel_register_name("indicatorName");
    objc_sel_t utf8_sel = g_sel_register_name("UTF8String");

    int has_idiom_factory = send_bool_sel(item_class, responds_sel, item_with_idiom_sel);
    int has_legacy_factory = send_bool_sel(item_class, responds_sel, item_sel);
    if (!has_idiom_factory && !has_legacy_factory) {
        set_error_locked("UIStatusBarItem factory unavailable");
        return -1;
    }

    int can_check_type = send_bool_sel(item_class, responds_sel, valid_sel);
    objc_id_t pool = create_autorelease_pool();
    for (int idiom = 0; idiom <= 1; idiom++) {
        for (int type = 0; type < 64; type++) {
            if (can_check_type && !send_bool_int(item_class, valid_sel, type)) continue;
            objc_id_t item = has_idiom_factory
                ? send_id_int_int(item_class, item_with_idiom_sel, type, idiom)
                : send_id_int(item_class, item_sel, type);
            if (!item || !send_bool_sel(item, responds_sel, indicator_sel)) continue;

            objc_id_t name = send_id(item, indicator_sel);
            if (!name || !send_bool_sel(name, responds_sel, utf8_sel)) continue;

            const char *text = send_cstring(name, utf8_sel);
            if (text && strcasecmp(text, "VPN") == 0) {
                drain_autorelease_pool(pool);
                return type;
            }
        }
    }
    drain_autorelease_pool(pool);
    set_error_locked("UIStatusBarItem with indicatorName VPN not found");
    return -1;
}

static int initialize_locked(void) {
    if (g_ready) return VPNICON_STATUSBAR_OK;
    if (g_unsupported) return VPNICON_STATUSBAR_UNSUPPORTED;

    if (g_ios_major < 0) g_ios_major = read_ios_major_version();
    if (g_ios_major < 0) {
        set_error_locked("cannot read iOS ProductVersion");
        return VPNICON_STATUSBAR_ERROR;
    }
    if (g_ios_major < 6 || g_ios_major > 10) {
        g_unsupported = 1;
        return VPNICON_STATUSBAR_UNSUPPORTED;
    }

    if (!g_objc_handle) g_objc_handle = dlopen(kObjCRuntimePath, RTLD_LAZY | RTLD_LOCAL);
    if (!g_objc_handle) {
        set_error_locked(dlerror());
        return VPNICON_STATUSBAR_ERROR;
    }
    if (!g_uikit_handle) g_uikit_handle = dlopen(kUIKitPath, RTLD_LAZY | RTLD_LOCAL);
    if (!g_uikit_handle) {
        set_error_locked(dlerror());
        return VPNICON_STATUSBAR_ERROR;
    }

    if (!g_objc_get_class &&
        load_function(g_objc_handle, "objc_getClass", &g_objc_get_class, sizeof(g_objc_get_class)) != 0) {
        set_error_locked("objc_getClass unavailable");
        return VPNICON_STATUSBAR_ERROR;
    }
    if (!g_sel_register_name &&
        load_function(g_objc_handle, "sel_registerName", &g_sel_register_name, sizeof(g_sel_register_name)) != 0) {
        set_error_locked("sel_registerName unavailable");
        return VPNICON_STATUSBAR_ERROR;
    }
    if (!g_msg_send &&
        load_function(g_objc_handle, "objc_msgSend", &g_msg_send, sizeof(g_msg_send)) != 0) {
        set_error_locked("objc_msgSend unavailable");
        return VPNICON_STATUSBAR_ERROR;
    }

    objc_id_t item_class = g_objc_get_class("UIStatusBarItem");
    g_status_bar_server = g_objc_get_class("UIStatusBarServer");
    if (!item_class || !g_status_bar_server) {
        set_error_locked("UIKit status bar classes unavailable");
        return VPNICON_STATUSBAR_ERROR;
    }

    objc_sel_t responds_sel = g_sel_register_name("respondsToSelector:");
    g_add_item_sel = g_sel_register_name("addStatusBarItem:");
    g_remove_item_sel = g_sel_register_name("removeStatusBarItem:");
    if (!send_bool_sel(g_status_bar_server, responds_sel, g_add_item_sel) ||
        !send_bool_sel(g_status_bar_server, responds_sel, g_remove_item_sel)) {
        set_error_locked("UIStatusBarServer add/remove methods unavailable");
        return VPNICON_STATUSBAR_ERROR;
    }

    g_vpn_item_type = find_vpn_item_type_locked(item_class);
    if (g_vpn_item_type < 0) return VPNICON_STATUSBAR_ERROR;

    g_last_error[0] = '\0';
    g_ready = 1;
    return VPNICON_STATUSBAR_OK;
}

int vpnicon_statusbar_set_enabled(int enabled) {
    pthread_mutex_lock(&g_lock);

    if (!enabled && !g_ready) {
        pthread_mutex_unlock(&g_lock);
        return VPNICON_STATUSBAR_OK;
    }

    int rc = initialize_locked();
    if (rc != VPNICON_STATUSBAR_OK) {
        pthread_mutex_unlock(&g_lock);
        return rc;
    }

    if (enabled) {
        if (!g_published) {
            send_void_int(g_status_bar_server, g_add_item_sel, g_vpn_item_type);
            g_published = 1;
        }
    } else if (g_published) {
        send_void_int(g_status_bar_server, g_remove_item_sel, g_vpn_item_type);
        g_published = 0;
    }

    pthread_mutex_unlock(&g_lock);
    return VPNICON_STATUSBAR_OK;
}

int vpnicon_statusbar_item_type(void) {
    pthread_mutex_lock(&g_lock);
    int type = g_vpn_item_type;
    pthread_mutex_unlock(&g_lock);
    return type;
}

const char *vpnicon_statusbar_last_error(void) {
    return g_last_error;
}
