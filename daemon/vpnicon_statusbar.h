#ifndef VLESSCORE_VPNICON_STATUSBAR_H
#define VLESSCORE_VPNICON_STATUSBAR_H

enum {
    VPNICON_STATUSBAR_OK = 0,
    VPNICON_STATUSBAR_UNSUPPORTED = 1,
    VPNICON_STATUSBAR_ERROR = -1,
};

int vpnicon_statusbar_set_enabled(int enabled);
int vpnicon_statusbar_item_type(void);
const char *vpnicon_statusbar_last_error(void);

#endif
