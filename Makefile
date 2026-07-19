ROOT := $(abspath .)
BUILD_DIR := $(ROOT)/build

IOS_TOOLCHAIN ?= $(HOME)/toolchains/ios6
IOS_SDK ?= $(IOS_TOOLCHAIN)/SDK/iPhoneOS6.1.sdk
IOS_BIN ?= $(IOS_TOOLCHAIN)/bin
IOS_CC ?= $(IOS_BIN)/arm-apple-darwin11-clang
IOS_AR ?= $(IOS_BIN)/arm-apple-darwin11-ar
IOS_RANLIB ?= $(IOS_BIN)/arm-apple-darwin11-ranlib
IOS_STRIP ?= $(IOS_BIN)/arm-apple-darwin11-strip
LDID ?= $(IOS_BIN)/ldid
IOS_BLOCKS_RUNTIME_LIB ?= libBlocksRuntime.so
IOS_BLOCKS_RUNTIME_DIR ?= $(shell \
	if [ -f "$(IOS_TOOLCHAIN)/lib/$(IOS_BLOCKS_RUNTIME_LIB)" ]; then \
		echo "$(IOS_TOOLCHAIN)/lib"; \
	elif [ -f "$(IOS_TOOLCHAIN)/lib64/$(IOS_BLOCKS_RUNTIME_LIB)" ]; then \
		echo "$(IOS_TOOLCHAIN)/lib64"; \
	else \
		find "$(IOS_TOOLCHAIN)" -maxdepth 5 -type f -name "$(IOS_BLOCKS_RUNTIME_LIB)" -print -quit 2>/dev/null | sed 's#/$(IOS_BLOCKS_RUNTIME_LIB)$$##'; \
	fi)
IOS_RUNTIME_ENV = LD_LIBRARY_PATH="$(IOS_BLOCKS_RUNTIME_DIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"

APP_NAME := vless-core
APP_BIN := $(BUILD_DIR)/$(APP_NAME)
DAEMON_BIN := $(BUILD_DIR)/vpnctld
BOOTSTRAP_BIN := $(BUILD_DIR)/vpnctld-bootstrap
PKG_ROOT := $(BUILD_DIR)/pkgroot
DEB_OUT := $(BUILD_DIR)/com.vlesscore.app_iphoneos-arm.deb

OPENSSL_IOS_DIR ?= $(abspath ../vless-core-cli/third_party/openssl-ios6-armv7)
OPENSSL_IOS_INCLUDE ?= $(OPENSSL_IOS_DIR)/include
OPENSSL_IOS_CRYPTO_LIB ?= $(OPENSSL_IOS_DIR)/lib/libcrypto.a

APP_SRC := app/main.m happ/happ_crypto.c third_party/quirc/quirc.c third_party/quirc/decode.c third_party/quirc/identify.c third_party/quirc/version_db.c
DAEMON_SRC := daemon/vpnctld.c daemon/vpnicon_statusbar.c
BOOTSTRAP_SRC := daemon/vpnctld_bootstrap.c

APP_CFLAGS := -fno-objc-arc -Wall -Wextra -O2 -arch armv7 -miphoneos-version-min=6.0 -isysroot $(IOS_SDK) -Ihapp -Ithird_party/quirc -I$(OPENSSL_IOS_INCLUDE)
APP_LDFLAGS := -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AVFoundation -framework CoreMedia -framework CoreVideo $(OPENSSL_IOS_CRYPTO_LIB)

DAEMON_CFLAGS := -Wall -Wextra -O2 -std=c11 -arch armv7 -miphoneos-version-min=6.0 -isysroot $(IOS_SDK)

VLESS_CORE_BIN ?= $(abspath ../vless-core-cli/vless-core-darwin-armv7)
VLESS_CORE_CURL_BIN ?= $(abspath ../vless-core-cli/third_party/curl-ios6-armv7/bin/curl)
OPENSSL_PATCH_STATUS_FILE ?= $(abspath ../vless-core-cli/third_party/openssl-ios6-armv7/VLESS_OPENSSL_PATCH_STATUS)
REDSOCKS_BIN ?= $(ROOT)/third_party/redsocks-vless-core
CA_BUNDLE ?= $(abspath ../vless-core-cli/third_party/cacert.pem)

all: deb

check-ios-toolchain:
	@test -x "$(IOS_CC)" || (echo "Missing iOS compiler: $(IOS_CC)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -x "$(IOS_AR)" || (echo "Missing iOS archiver: $(IOS_AR)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -x "$(IOS_RANLIB)" || (echo "Missing iOS ranlib: $(IOS_RANLIB)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -x "$(IOS_STRIP)" || (echo "Missing iOS strip: $(IOS_STRIP)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -d "$(IOS_SDK)" || (echo "Missing iOS SDK: $(IOS_SDK)"; echo "Set IOS_SDK=/path/to/iPhoneOS6.1.sdk"; exit 1)
	@test -f "$(OPENSSL_IOS_INCLUDE)/openssl/evp.h" || (echo "Missing OpenSSL headers: $(OPENSSL_IOS_INCLUDE)"; echo "Build OpenSSL in ../vless-core-cli or override OPENSSL_IOS_DIR"; exit 1)
	@test -f "$(OPENSSL_IOS_CRYPTO_LIB)" || (echo "Missing OpenSSL crypto library: $(OPENSSL_IOS_CRYPTO_LIB)"; echo "Build OpenSSL in ../vless-core-cli or override OPENSSL_IOS_DIR"; exit 1)
	@test -n "$(IOS_BLOCKS_RUNTIME_DIR)" || (echo "Missing $(IOS_BLOCKS_RUNTIME_LIB) under $(IOS_TOOLCHAIN)"; echo "Add it to the toolchain or set IOS_BLOCKS_RUNTIME_DIR=/path/to/runtime/lib"; exit 1)
	@test -x "$(LDID)" || (echo "Missing ldid tool: $(LDID)"; echo "Set IOS_TOOLCHAIN correctly or override LDID"; exit 1)

check-package-inputs:
	@test -f "$(VLESS_CORE_BIN)" || (echo "Missing core binary: $(VLESS_CORE_BIN)"; echo "Build it in ../vless-core-cli or override VLESS_CORE_BIN=/path/to/vless-core-darwin-armv7"; exit 1)
	@test -f "$(VLESS_CORE_CURL_BIN)" || (echo "Missing curl binary: $(VLESS_CORE_CURL_BIN)"; echo "Build it in ../vless-core-cli (make curl-ios6) or override VLESS_CORE_CURL_BIN=/path/to/curl"; exit 1)
	@test -f "$(REDSOCKS_BIN)" || (echo "Missing redsocks binary: $(REDSOCKS_BIN)"; exit 1)
	@test -f "$(CA_BUNDLE)" || (echo "Missing CA bundle: $(CA_BUNDLE)"; echo "Provide CA_BUNDLE=/path/to/cacert.pem"; exit 1)
	@if [ -f "$(OPENSSL_PATCH_STATUS_FILE)" ] && [ "$(OPENSSL_PATCH_STATUS_FILE)" -nt "$(VLESS_CORE_BIN)" ]; then \
		echo "Stale core binary: $(VLESS_CORE_BIN) is older than $(OPENSSL_PATCH_STATUS_FILE)"; \
		echo "Rebuild it in ../vless-core-cli after changing OpenSSL: make ios"; \
		exit 1; \
	fi
	@if [ -f "$(OPENSSL_PATCH_STATUS_FILE)" ] && [ "$(OPENSSL_PATCH_STATUS_FILE)" -nt "$(VLESS_CORE_CURL_BIN)" ]; then \
		echo "Stale curl binary: $(VLESS_CORE_CURL_BIN) is older than $(OPENSSL_PATCH_STATUS_FILE)"; \
		echo "Rebuild it in ../vless-core-cli after changing OpenSSL: make curl-ios6"; \
		exit 1; \
	fi

$(APP_BIN): check-ios-toolchain $(APP_SRC)
	mkdir -p $(BUILD_DIR)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(APP_CFLAGS) $(APP_SRC) -o $@ $(APP_LDFLAGS)

$(DAEMON_BIN): check-ios-toolchain $(DAEMON_SRC)
	mkdir -p $(BUILD_DIR)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(DAEMON_CFLAGS) $(DAEMON_SRC) -o $@

$(BOOTSTRAP_BIN): check-ios-toolchain $(BOOTSTRAP_SRC)
	mkdir -p $(BUILD_DIR)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(DAEMON_CFLAGS) $(BOOTSTRAP_SRC) -o $@

app: $(APP_BIN)

daemon: $(DAEMON_BIN)

package-root: check-package-inputs $(APP_BIN) $(DAEMON_BIN) $(BOOTSTRAP_BIN)
	mkdir -p $(PKG_ROOT)
	mkdir -p packaging/Applications/vless-core.app packaging/usr/bin
	rm -rf $(PKG_ROOT)/*
	cp -a packaging/DEBIAN $(PKG_ROOT)/
	cp -a packaging/Applications $(PKG_ROOT)/
	cp -a packaging/Library $(PKG_ROOT)/
	cp -a packaging/usr $(PKG_ROOT)/
	cp app/Info.plist $(PKG_ROOT)/Applications/vless-core.app/Info.plist
	BUILD_DATE="$$(date -u '+%Y-%m-%d %H:%M:%S UTC')"; \
	GIT_COMMIT="$$(git -C "$(ROOT)" rev-parse --short=7 --verify HEAD 2>/dev/null)"; \
	[ -n "$$GIT_COMMIT" ] || GIT_COMMIT=unknown; \
	sed -i "/<key>VCBuildDate<\/key>/{n;s#<string>.*</string>#<string>$$BUILD_DATE</string>#;}" $(PKG_ROOT)/Applications/vless-core.app/Info.plist; \
	sed -i "/<key>VCGitCommit<\/key>/{n;s#<string>.*</string>#<string>$$GIT_COMMIT</string>#;}" $(PKG_ROOT)/Applications/vless-core.app/Info.plist
	cp app/icons/Icon.png $(PKG_ROOT)/Applications/vless-core.app/Icon.png
	cp app/icons/Icon@2x.png $(PKG_ROOT)/Applications/vless-core.app/Icon@2x.png
	cp app/icons/icon-refresh.png $(PKG_ROOT)/Applications/vless-core.app/icon-refresh.png
	cp app/icons/icon-terminal.png $(PKG_ROOT)/Applications/vless-core.app/icon-terminal.png
	cp app/icons/icon-list.png $(PKG_ROOT)/Applications/vless-core.app/icon-list.png
	cp app/icons/icon-settings.png $(PKG_ROOT)/Applications/vless-core.app/icon-settings.png
	cp app/icons/icon-trash.png $(PKG_ROOT)/Applications/vless-core.app/icon-trash.png
	cp app/icons/icon-ping.png $(PKG_ROOT)/Applications/vless-core.app/icon-ping.png
	cp app/icons/info.png $(PKG_ROOT)/Applications/vless-core.app/info.png
	cp $(APP_BIN) $(PKG_ROOT)/Applications/vless-core.app/vless-core
	cp $(DAEMON_BIN) $(PKG_ROOT)/usr/bin/vpnctld
	cp $(BOOTSTRAP_BIN) $(PKG_ROOT)/usr/bin/vpnctld-bootstrap
	cp $(VLESS_CORE_BIN) $(PKG_ROOT)/usr/bin/vless-core-darwin-armv7
	cp $(VLESS_CORE_CURL_BIN) $(PKG_ROOT)/usr/bin/vless-core-curl
	cp $(REDSOCKS_BIN) $(PKG_ROOT)/usr/bin/redsocks-vless-core
	mkdir -p $(PKG_ROOT)/usr/share/vless-core
	cp $(CA_BUNDLE) $(PKG_ROOT)/usr/share/vless-core/cacert.pem
	if [ -f "$(OPENSSL_PATCH_STATUS_FILE)" ]; then \
		cp "$(OPENSSL_PATCH_STATUS_FILE)" $(PKG_ROOT)/usr/share/vless-core/openssl-patch-status; \
	else \
		printf '%s\n' unpatched > $(PKG_ROOT)/usr/share/vless-core/openssl-patch-status; \
	fi
	find $(PKG_ROOT) -type d -exec chmod 755 {} \;
	find $(PKG_ROOT) -type f -exec chmod 644 {} \;
	chmod 755 $(PKG_ROOT)/Applications/vless-core.app/vless-core
	chmod 755 $(PKG_ROOT)/usr/bin/vpnctld
	chmod 4755 $(PKG_ROOT)/usr/bin/vpnctld-bootstrap
	chmod 755 $(PKG_ROOT)/usr/bin/vless-core-darwin-armv7
	chmod 755 $(PKG_ROOT)/usr/bin/vless-core-curl
	chmod 755 $(PKG_ROOT)/usr/bin/redsocks-vless-core
	for script in preinst postinst prerm postrm; do \
		[ -f "$(PKG_ROOT)/DEBIAN/$$script" ] && chmod 755 "$(PKG_ROOT)/DEBIAN/$$script" || true; \
	done
	$(LDID) -S $(PKG_ROOT)/Applications/vless-core.app/vless-core
	$(LDID) -S $(PKG_ROOT)/usr/bin/vpnctld
	$(LDID) -S $(PKG_ROOT)/usr/bin/vpnctld-bootstrap
	$(LDID) -S $(PKG_ROOT)/usr/bin/vless-core-darwin-armv7
	$(LDID) -S $(PKG_ROOT)/usr/bin/vless-core-curl
	$(LDID) -S $(PKG_ROOT)/usr/bin/redsocks-vless-core
	chmod 4755 $(PKG_ROOT)/usr/bin/vpnctld-bootstrap

tarball: package-root
	cd $(BUILD_DIR) && tar -czf vless-core-app-bundle.tar.gz -C pkgroot .

deb: package-root
	rm -f $(BUILD_DIR)/com.vlesscore.app*_iphoneos-arm.deb
	dpkg-deb --uniform-compression -Zgzip -z6 --root-owner-group -b $(PKG_ROOT) $(DEB_OUT)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all app daemon check-ios-toolchain check-package-inputs package-root deb clean tarball
