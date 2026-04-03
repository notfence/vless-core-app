ROOT := $(abspath .)
BUILD_DIR := $(ROOT)/build

IOS_TOOLCHAIN ?= $(HOME)/toolchains/ios6
IOS_SDK ?= $(IOS_TOOLCHAIN)/SDK/iPhoneOS6.1.sdk
IOS_BIN ?= $(IOS_TOOLCHAIN)/bin
IOS_CC ?= $(IOS_BIN)/arm-apple-darwin11-clang
IOS_STRIP ?= $(IOS_BIN)/arm-apple-darwin11-strip
LDID ?= $(IOS_BIN)/ldid

APP_NAME := vless-core
APP_BIN := $(BUILD_DIR)/$(APP_NAME)
DAEMON_BIN := $(BUILD_DIR)/vpnctld
BOOTSTRAP_BIN := $(BUILD_DIR)/vpnctld-bootstrap
VPNICON_TWEAK_BIN := $(BUILD_DIR)/vlesscorevpnicon.dylib
PKG_ROOT := $(BUILD_DIR)/pkgroot
DEB_OUT := $(BUILD_DIR)/com.vlesscore.app_iphoneos-arm.deb

APP_SRC := app/main.m
DAEMON_SRC := daemon/vpnctld.c
BOOTSTRAP_SRC := daemon/vpnctld_bootstrap.c
VPNICON_TWEAK_SRC := tweak/vlesscore_vpnicon.m

APP_CFLAGS := -fno-objc-arc -Wall -Wextra -O2 -arch armv7 -miphoneos-version-min=6.0 -isysroot $(IOS_SDK)
APP_LDFLAGS := -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore

DAEMON_CFLAGS := -Wall -Wextra -O2 -std=c11 -arch armv7 -miphoneos-version-min=6.0 -isysroot $(IOS_SDK)
TWEAK_CFLAGS := -fno-objc-arc -Wall -Wextra -O2 -arch armv7 -miphoneos-version-min=6.0 -isysroot $(IOS_SDK)
TWEAK_LDFLAGS := -dynamiclib -install_name /Library/MobileSubstrate/DynamicLibraries/vlesscorevpnicon.dylib -framework Foundation -framework UIKit -framework CoreFoundation

VLESS_CORE_BIN ?= $(abspath ../vless-core-cli/vless-core-darwin-amrv7)
VLESS_CORE_CURL_BIN ?= $(abspath ../vless-core-cli/third_party/curl-ios6-armv7/bin/curl)
REDSOCKS_BIN ?= $(ROOT)/third_party/redsocks-vless-core
CA_BUNDLE ?= $(abspath ../vless-core-cli/third_party/cacert.pem)

all: deb

check-ios-toolchain:
	@test -x "$(IOS_CC)" || (echo "Missing iOS compiler: $(IOS_CC)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -d "$(IOS_SDK)" || (echo "Missing iOS SDK: $(IOS_SDK)"; echo "Set IOS_SDK=/path/to/iPhoneOS6.1.sdk"; exit 1)
	@test -x "$(LDID)" || (echo "Missing ldid tool: $(LDID)"; echo "Set IOS_TOOLCHAIN correctly or override LDID"; exit 1)

check-package-inputs:
	@test -f "$(VLESS_CORE_BIN)" || (echo "Missing core binary: $(VLESS_CORE_BIN)"; echo "Build it in ../vless-core-cli or override VLESS_CORE_BIN=/path/to/vless-core-darwin-amrv7"; exit 1)
	@test -f "$(VLESS_CORE_CURL_BIN)" || (echo "Missing curl binary: $(VLESS_CORE_CURL_BIN)"; echo "Build it in ../vless-core-cli (make curl-ios6) or override VLESS_CORE_CURL_BIN=/path/to/curl"; exit 1)
	@test -f "$(REDSOCKS_BIN)" || (echo "Missing redsocks binary: $(REDSOCKS_BIN)"; exit 1)
	@test -f "$(CA_BUNDLE)" || (echo "Missing CA bundle: $(CA_BUNDLE)"; echo "Provide CA_BUNDLE=/path/to/cacert.pem"; exit 1)

$(APP_BIN): check-ios-toolchain $(APP_SRC)
	mkdir -p $(BUILD_DIR)
	PATH="$(IOS_BIN):$$PATH" $(IOS_CC) $(APP_CFLAGS) $(APP_SRC) -o $@ $(APP_LDFLAGS)

$(DAEMON_BIN): check-ios-toolchain $(DAEMON_SRC)
	mkdir -p $(BUILD_DIR)
	PATH="$(IOS_BIN):$$PATH" $(IOS_CC) $(DAEMON_CFLAGS) $(DAEMON_SRC) -o $@

$(BOOTSTRAP_BIN): check-ios-toolchain $(BOOTSTRAP_SRC)
	mkdir -p $(BUILD_DIR)
	PATH="$(IOS_BIN):$$PATH" $(IOS_CC) $(DAEMON_CFLAGS) $(BOOTSTRAP_SRC) -o $@

$(VPNICON_TWEAK_BIN): check-ios-toolchain $(VPNICON_TWEAK_SRC)
	mkdir -p $(BUILD_DIR)
	PATH="$(IOS_BIN):$$PATH" $(IOS_CC) $(TWEAK_CFLAGS) $(VPNICON_TWEAK_SRC) -o $@ $(TWEAK_LDFLAGS)

app: $(APP_BIN)

daemon: $(DAEMON_BIN)

package-root: check-package-inputs $(APP_BIN) $(DAEMON_BIN) $(BOOTSTRAP_BIN) $(VPNICON_TWEAK_BIN)
	mkdir -p $(PKG_ROOT)
	rm -rf $(PKG_ROOT)/*
	cp -a packaging/DEBIAN $(PKG_ROOT)/
	cp -a packaging/Applications $(PKG_ROOT)/
	cp -a packaging/Library $(PKG_ROOT)/
	cp -a packaging/usr $(PKG_ROOT)/
	cp app/Info.plist $(PKG_ROOT)/Applications/vless-core.app/Info.plist
	cp app/icons/Icon.png $(PKG_ROOT)/Applications/vless-core.app/Icon.png
	cp app/icons/Icon@2x.png $(PKG_ROOT)/Applications/vless-core.app/Icon@2x.png
	cp app/icons/icon-refresh.png $(PKG_ROOT)/Applications/vless-core.app/icon-refresh.png
	cp app/icons/icon-terminal.png $(PKG_ROOT)/Applications/vless-core.app/icon-terminal.png
	cp app/icons/icon-list.png $(PKG_ROOT)/Applications/vless-core.app/icon-list.png
	cp app/icons/icon-settings.png $(PKG_ROOT)/Applications/vless-core.app/icon-settings.png
	cp app/icons/icon-ping.png $(PKG_ROOT)/Applications/vless-core.app/icon-ping.png
	cp $(APP_BIN) $(PKG_ROOT)/Applications/vless-core.app/vless-core
	cp $(DAEMON_BIN) $(PKG_ROOT)/usr/bin/vpnctld
	cp $(BOOTSTRAP_BIN) $(PKG_ROOT)/usr/bin/vpnctld-bootstrap
	cp $(VPNICON_TWEAK_BIN) $(PKG_ROOT)/Library/MobileSubstrate/DynamicLibraries/vlesscorevpnicon.dylib
	cp $(VLESS_CORE_BIN) $(PKG_ROOT)/usr/bin/vless-core-darwin-amrv7
	cp $(VLESS_CORE_CURL_BIN) $(PKG_ROOT)/usr/bin/vless-core-curl
	cp $(REDSOCKS_BIN) $(PKG_ROOT)/usr/bin/redsocks-vless-core
	mkdir -p $(PKG_ROOT)/usr/share/vless-core
	cp $(CA_BUNDLE) $(PKG_ROOT)/usr/share/vless-core/cacert.pem
	find $(PKG_ROOT) -type d -exec chmod 755 {} \;
	find $(PKG_ROOT) -type f -exec chmod 644 {} \;
	chmod 755 $(PKG_ROOT)/Applications/vless-core.app/vless-core
	chmod 755 $(PKG_ROOT)/usr/bin/vpnctld
	chmod 4755 $(PKG_ROOT)/usr/bin/vpnctld-bootstrap
	chmod 755 $(PKG_ROOT)/usr/bin/vless-core-darwin-amrv7
	chmod 755 $(PKG_ROOT)/usr/bin/vless-core-curl
	chmod 755 $(PKG_ROOT)/usr/bin/redsocks-vless-core
	chmod 755 $(PKG_ROOT)/Library/MobileSubstrate/DynamicLibraries/vlesscorevpnicon.dylib
	chmod 755 $(PKG_ROOT)/DEBIAN/postinst $(PKG_ROOT)/DEBIAN/prerm
	$(LDID) -S $(PKG_ROOT)/Applications/vless-core.app/vless-core
	$(LDID) -S $(PKG_ROOT)/usr/bin/vpnctld
	$(LDID) -S $(PKG_ROOT)/usr/bin/vpnctld-bootstrap
	$(LDID) -S $(PKG_ROOT)/usr/bin/vless-core-darwin-amrv7
	$(LDID) -S $(PKG_ROOT)/usr/bin/vless-core-curl
	$(LDID) -S $(PKG_ROOT)/usr/bin/redsocks-vless-core
	$(LDID) -S $(PKG_ROOT)/Library/MobileSubstrate/DynamicLibraries/vlesscorevpnicon.dylib
	chmod 4755 $(PKG_ROOT)/usr/bin/vpnctld-bootstrap

tarball: package-root
	cd $(BUILD_DIR) && tar -czf vless-core-app-bundle.tar.gz -C pkgroot .

deb: package-root
	rm -f $(BUILD_DIR)/com.vlesscore.app*_iphoneos-arm.deb
	dpkg-deb --uniform-compression -Zgzip -z6 --root-owner-group -b $(PKG_ROOT) $(DEB_OUT)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all app daemon check-ios-toolchain check-package-inputs package-root deb clean tarball
