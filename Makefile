ROOT := $(abspath .)
BUILD_DIR := $(ROOT)/build
LEGAL_DIR := $(ROOT)/legal

IOS_TOOLCHAIN ?= $(abspath ../toolchains/ios6)
IOS_SDK ?= $(IOS_TOOLCHAIN)/SDK/iPhoneOS6.1.sdk
APP_IOS_SDK ?= $(abspath ../toolchains/sdks/iPhoneOS10.3.sdk)
APP_IOS_SDK_VERSION ?= 10.3
ARM64_IOS_SDK ?= $(abspath ../toolchains/sdks/iPhoneOS11.4.sdk)
ARM64_IOS_MIN_VERSION ?= 11.0
IOS_BIN ?= $(IOS_TOOLCHAIN)/bin
IOS_CC ?= $(IOS_BIN)/arm-apple-darwin11-clang
IOS_AR ?= $(IOS_BIN)/arm-apple-darwin11-ar
IOS_RANLIB ?= $(IOS_BIN)/arm-apple-darwin11-ranlib
IOS_STRIP ?= $(IOS_BIN)/arm-apple-darwin11-strip
IOS_OTOOL ?= $(IOS_BIN)/arm-apple-darwin11-otool
IOS_LIPO ?= $(IOS_BIN)/arm-apple-darwin11-lipo
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
APP_ARMV7_BIN := $(BUILD_DIR)/armv7/$(APP_NAME)
APP_ARM64_BIN := $(BUILD_DIR)/arm64/$(APP_NAME)
DAEMON_ARMV7_BIN := $(BUILD_DIR)/armv7/vpnctld
DAEMON_ARM64_BIN := $(BUILD_DIR)/arm64/vpnctld
BOOTSTRAP_ARMV7_BIN := $(BUILD_DIR)/armv7/vpnctld-bootstrap
BOOTSTRAP_ARM64_BIN := $(BUILD_DIR)/arm64/vpnctld-bootstrap
PKG_ROOT := $(BUILD_DIR)/pkgroot
DEB_OUT := $(BUILD_DIR)/com.vlesscore.app_iphoneos-arm.deb
APP_ENTITLEMENTS := $(ROOT)/packaging/app-entitlements.xml
DAEMON_ENTITLEMENTS := $(ROOT)/packaging/daemon-entitlements.xml

OPENSSL_IOS_DIR ?= $(abspath ../vless-core-cli/third_party/openssl-ios6-armv7)
OPENSSL_IOS_INCLUDE ?= $(OPENSSL_IOS_DIR)/include
OPENSSL_IOS_SSL_LIB ?= $(OPENSSL_IOS_DIR)/lib/libssl.a
OPENSSL_IOS_CRYPTO_LIB ?= $(OPENSSL_IOS_DIR)/lib/libcrypto.a
OPENSSL_IOS_ARM64_DIR ?= $(abspath ../vless-core-cli/third_party/openssl-ios-arm64)
OPENSSL_IOS_ARM64_INCLUDE ?= $(OPENSSL_IOS_ARM64_DIR)/include
OPENSSL_IOS_ARM64_SSL_LIB ?= $(OPENSSL_IOS_ARM64_DIR)/lib/libssl.a
OPENSSL_IOS_ARM64_CRYPTO_LIB ?= $(OPENSSL_IOS_ARM64_DIR)/lib/libcrypto.a

ZBAR_DIR := third_party/zbar/zbar
ZBAR_SRC := \
	$(ZBAR_DIR)/config.c \
	$(ZBAR_DIR)/decoder/qr_finder.c \
	$(ZBAR_DIR)/decoder.c \
	$(ZBAR_DIR)/error.c \
	$(ZBAR_DIR)/image.c \
	$(ZBAR_DIR)/img_scanner.c \
	$(ZBAR_DIR)/qrcode/bch15_5.c \
	$(ZBAR_DIR)/qrcode/binarize.c \
	$(ZBAR_DIR)/qrcode/isaac.c \
	$(ZBAR_DIR)/qrcode/qrdec.c \
	$(ZBAR_DIR)/qrcode/qrdectxt.c \
	$(ZBAR_DIR)/qrcode/rs.c \
	$(ZBAR_DIR)/qrcode/util.c \
	$(ZBAR_DIR)/refcnt.c \
	$(ZBAR_DIR)/scanner.c \
	$(ZBAR_DIR)/symbol.c
ZBAR_HEADERS := $(shell find $(ZBAR_DIR) -type f -name '*.h')
ZBAR_OBJ := $(patsubst $(ZBAR_DIR)/%.c,$(BUILD_DIR)/zbar/%.o,$(ZBAR_SRC))
ZBAR_LIB := $(BUILD_DIR)/libzbar-qr.a
ZBAR_ARM64_OBJ := $(patsubst $(ZBAR_DIR)/%.c,$(BUILD_DIR)/arm64/zbar/%.o,$(ZBAR_SRC))
ZBAR_ARM64_LIB := $(BUILD_DIR)/arm64/libzbar-qr.a

APP_SRC := app/main.m integrations/happ/happ_crypto.c integrations/karing/karing_backup.m
APP_HEADERS := integrations/happ/happ_crypto.h integrations/karing/karing_backup.h daemon/vpnctld_protocol.h
APP_OBJ := \
	$(patsubst %.m,$(BUILD_DIR)/app/%.o,$(filter %.m,$(APP_SRC))) \
	$(patsubst %.c,$(BUILD_DIR)/app/%.o,$(filter %.c,$(APP_SRC)))
APP_ARM64_OBJ := \
	$(patsubst %.m,$(BUILD_DIR)/arm64/app/%.o,$(filter %.m,$(APP_SRC))) \
	$(patsubst %.c,$(BUILD_DIR)/arm64/app/%.o,$(filter %.c,$(APP_SRC)))
DAEMON_SRC := daemon/vpnctld.c daemon/vpnicon_statusbar.c daemon/system_proxy.c
DAEMON_HEADERS := daemon/vpnctld_protocol.h daemon/system_proxy.h
BOOTSTRAP_SRC := daemon/vpnctld_bootstrap.c

APP_CFLAGS := -fno-objc-arc -Wall -Wextra -O2 -arch armv7 -miphoneos-version-min=6.0 -isysroot $(APP_IOS_SDK) -Iintegrations/happ -Iintegrations/karing -I$(ZBAR_DIR) -I$(OPENSSL_IOS_INCLUDE)
APP_LDFLAGS := -Wl,-pie -Wl,-platform_version,ios,6.0,$(APP_IOS_SDK_VERSION) -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework SystemConfiguration -liconv -lsqlite3 -lz $(OPENSSL_IOS_CRYPTO_LIB)
ZBAR_CFLAGS := -w -O2 -arch armv7 -miphoneos-version-min=6.0 -isysroot $(APP_IOS_SDK) -I$(ZBAR_DIR)
APP_ARM64_CFLAGS := -fno-objc-arc -Wall -Wextra -O2 -arch arm64 -miphoneos-version-min=$(ARM64_IOS_MIN_VERSION) -isysroot $(ARM64_IOS_SDK) -Iintegrations/happ -Iintegrations/karing -I$(ZBAR_DIR) -I$(OPENSSL_IOS_ARM64_INCLUDE)
APP_ARM64_LDFLAGS := -Wl,-pie -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework SystemConfiguration -liconv -lsqlite3 -lz $(OPENSSL_IOS_ARM64_CRYPTO_LIB)
ZBAR_ARM64_CFLAGS := -w -O2 -arch arm64 -miphoneos-version-min=$(ARM64_IOS_MIN_VERSION) -isysroot $(ARM64_IOS_SDK) -I$(ZBAR_DIR)
ARM64_RUNTIME_DEFINES := -DVC_CORE_EXECUTABLE_PATH='"/usr/bin/vless-core-darwin-arm64"' -DVC_CORE_EXECUTABLE_NAME='"vless-core-darwin-arm64"'
APP_ARM64_CFLAGS += $(ARM64_RUNTIME_DEFINES)

DAEMON_CFLAGS := -Wall -Wextra -O2 -std=c11 -arch armv7 -miphoneos-version-min=6.0 -isysroot $(IOS_SDK)
DAEMON_LDFLAGS := -Wl,-pie
DAEMON_ARM64_CFLAGS := -Wall -Wextra -O2 -std=c11 -arch arm64 -miphoneos-version-min=$(ARM64_IOS_MIN_VERSION) -isysroot $(ARM64_IOS_SDK) $(ARM64_RUNTIME_DEFINES)
DAEMON_ARM64_LDFLAGS := -Wl,-pie -framework CoreFoundation
BOOTSTRAP_ARM64_LDFLAGS := -Wl,-pie

VLESS_CORE_BIN ?= $(abspath ../vless-core-cli/vless-core-darwin-armv7)
VLESS_CORE_ARM64_BIN ?= $(abspath ../vless-core-cli/vless-core-darwin-arm64)
VLESS_CORE_CURL_BIN ?= $(abspath ../vless-core-cli/third_party/curl-ios6-armv7/bin/curl)
VLESS_CORE_CURL_ARM64_BIN ?= $(abspath ../vless-core-cli/third_party/curl-ios-arm64/bin/curl)
OPENSSL_PATCH_STATUS_FILE ?= $(abspath ../vless-core-cli/third_party/openssl-ios6-armv7/VLESS_OPENSSL_PATCH_STATUS)
OPENSSL_ARM64_PATCH_STATUS_FILE ?= $(abspath ../vless-core-cli/third_party/openssl-ios-arm64/VLESS_OPENSSL_PATCH_STATUS)
REDSOCKS_BIN ?= $(ROOT)/third_party/redsocks-vless-core
REDSOCKS_ARM64_BIN ?= $(ROOT)/third_party/redsocks-vless-core-arm64
CA_BUNDLE ?= $(abspath ../vless-core-cli/third_party/cacert.pem)

all: deb

check-ios-toolchain:
	@test -x "$(IOS_CC)" || (echo "Missing iOS compiler: $(IOS_CC)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -x "$(IOS_AR)" || (echo "Missing iOS archiver: $(IOS_AR)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -x "$(IOS_RANLIB)" || (echo "Missing iOS ranlib: $(IOS_RANLIB)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -x "$(IOS_STRIP)" || (echo "Missing iOS strip: $(IOS_STRIP)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -x "$(IOS_OTOOL)" || (echo "Missing iOS otool: $(IOS_OTOOL)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -x "$(IOS_LIPO)" || (echo "Missing iOS lipo: $(IOS_LIPO)"; echo "Set IOS_TOOLCHAIN=/path/to/ios6/toolchain"; exit 1)
	@test -d "$(IOS_SDK)" || (echo "Missing iOS SDK: $(IOS_SDK)"; echo "Set IOS_SDK=/path/to/iPhoneOS6.1.sdk"; exit 1)
	@test -d "$(APP_IOS_SDK)" || (echo "Missing app SDK: $(APP_IOS_SDK)"; echo "Set APP_IOS_SDK=/path/to/iPhoneOS10.3.sdk"; exit 1)
	@test -d "$(ARM64_IOS_SDK)" || (echo "Missing arm64 iOS SDK: $(ARM64_IOS_SDK)"; echo "Set ARM64_IOS_SDK=/path/to/iPhoneOS11.4.sdk"; exit 1)
	@test -f "$(OPENSSL_IOS_INCLUDE)/openssl/evp.h" || (echo "Missing OpenSSL headers: $(OPENSSL_IOS_INCLUDE)"; echo "Build OpenSSL in ../vless-core-cli or override OPENSSL_IOS_DIR"; exit 1)
	@test -f "$(OPENSSL_IOS_SSL_LIB)" || (echo "Missing OpenSSL SSL library: $(OPENSSL_IOS_SSL_LIB)"; echo "Build OpenSSL in ../vless-core-cli or override OPENSSL_IOS_DIR"; exit 1)
	@test -f "$(OPENSSL_IOS_CRYPTO_LIB)" || (echo "Missing OpenSSL crypto library: $(OPENSSL_IOS_CRYPTO_LIB)"; echo "Build OpenSSL in ../vless-core-cli or override OPENSSL_IOS_DIR"; exit 1)
	@test -f "$(OPENSSL_IOS_ARM64_INCLUDE)/openssl/evp.h" || (echo "Missing arm64 OpenSSL headers: $(OPENSSL_IOS_ARM64_INCLUDE)"; echo "Run make openssl-ios-arm64 in ../vless-core-cli"; exit 1)
	@test -f "$(OPENSSL_IOS_ARM64_SSL_LIB)" || (echo "Missing arm64 OpenSSL SSL library: $(OPENSSL_IOS_ARM64_SSL_LIB)"; echo "Run make openssl-ios-arm64 in ../vless-core-cli"; exit 1)
	@test -f "$(OPENSSL_IOS_ARM64_CRYPTO_LIB)" || (echo "Missing arm64 OpenSSL crypto library: $(OPENSSL_IOS_ARM64_CRYPTO_LIB)"; echo "Run make openssl-ios-arm64 in ../vless-core-cli"; exit 1)
	@test -n "$(IOS_BLOCKS_RUNTIME_DIR)" || (echo "Missing $(IOS_BLOCKS_RUNTIME_LIB) under $(IOS_TOOLCHAIN)"; echo "Add it to the toolchain or set IOS_BLOCKS_RUNTIME_DIR=/path/to/runtime/lib"; exit 1)
	@test -x "$(LDID)" || (echo "Missing ldid tool: $(LDID)"; echo "Set IOS_TOOLCHAIN correctly or override LDID"; exit 1)
	@test -f "$(APP_ENTITLEMENTS)" || (echo "Missing app entitlements: $(APP_ENTITLEMENTS)"; exit 1)
	@test -f "$(DAEMON_ENTITLEMENTS)" || (echo "Missing daemon entitlements: $(DAEMON_ENTITLEMENTS)"; exit 1)

check-package-inputs:
	@test -f "$(VLESS_CORE_BIN)" || (echo "Missing armv7 core binary: $(VLESS_CORE_BIN)"; echo "Run make ios in ../vless-core-cli"; exit 1)
	@test -f "$(VLESS_CORE_ARM64_BIN)" || (echo "Missing arm64 core binary: $(VLESS_CORE_ARM64_BIN)"; echo "Run make ios-arm64 in ../vless-core-cli"; exit 1)
	@test -f "$(VLESS_CORE_CURL_BIN)" || (echo "Missing armv7 curl binary: $(VLESS_CORE_CURL_BIN)"; echo "Run make curl-ios6 in ../vless-core-cli"; exit 1)
	@test -f "$(VLESS_CORE_CURL_ARM64_BIN)" || (echo "Missing arm64 curl binary: $(VLESS_CORE_CURL_ARM64_BIN)"; echo "Run make curl-ios-arm64 in ../vless-core-cli"; exit 1)
	@test -f "$(REDSOCKS_BIN)" || (echo "Missing armv7 redsocks binary: $(REDSOCKS_BIN)"; exit 1)
	@test -f "$(REDSOCKS_ARM64_BIN)" || (echo "Missing arm64 redsocks binary: $(REDSOCKS_ARM64_BIN)"; exit 1)
	@test -f "$(CA_BUNDLE)" || (echo "Missing CA bundle: $(CA_BUNDLE)"; echo "Provide CA_BUNDLE=/path/to/cacert.pem"; exit 1)
	@test -f "$(OPENSSL_ARM64_PATCH_STATUS_FILE)" || (echo "Missing arm64 OpenSSL patch status: $(OPENSSL_ARM64_PATCH_STATUS_FILE)"; echo "Run make openssl-ios-arm64 in ../vless-core-cli"; exit 1)
	@test -f "$(ROOT)/LICENSE" || (echo "Missing project license"; exit 1)
	@test -f "$(LEGAL_DIR)/THIRD_PARTY_LICENSES.txt" || (echo "Missing third-party license information"; exit 1)
	@test -f "$(ROOT)/third_party/zbar/COPYING" || (echo "Missing ZBar notices"; exit 1)
	@for binary in "$(VLESS_CORE_BIN)" "$(VLESS_CORE_CURL_BIN)" "$(REDSOCKS_BIN)"; do \
		$(IOS_LIPO) -info "$$binary" | grep -q 'architecture: armv7' || { echo "Refusing non-armv7 legacy binary: $$binary"; exit 1; }; \
		$(IOS_OTOOL) -hv "$$binary" | grep -qw PIE || { echo "Refusing non-PIE armv7 binary: $$binary"; exit 1; }; \
	done
	@for binary in "$(VLESS_CORE_ARM64_BIN)" "$(VLESS_CORE_CURL_ARM64_BIN)" "$(REDSOCKS_ARM64_BIN)"; do \
		$(IOS_LIPO) -info "$$binary" | grep -q 'architecture: arm64' || { echo "Refusing non-arm64 modern binary: $$binary"; exit 1; }; \
		$(IOS_OTOOL) -hv "$$binary" | grep -qw PIE || { echo "Refusing non-PIE arm64 binary: $$binary"; exit 1; }; \
	done
	@for dependency in "$(OPENSSL_PATCH_STATUS_FILE)" "$(OPENSSL_IOS_SSL_LIB)" "$(OPENSSL_IOS_CRYPTO_LIB)"; do \
		if [ -f "$$dependency" ] && [ "$$dependency" -nt "$(VLESS_CORE_BIN)" ]; then \
			echo "Stale core binary: $(VLESS_CORE_BIN) is older than $$dependency"; \
			echo "Rebuild it in ../vless-core-cli after changing OpenSSL: make ios"; \
			exit 1; \
		fi; \
	done
	@for dependency in "$(OPENSSL_IOS_ARM64_SSL_LIB)" "$(OPENSSL_IOS_ARM64_CRYPTO_LIB)"; do \
		if [ "$$dependency" -nt "$(VLESS_CORE_ARM64_BIN)" ]; then \
			echo "Stale arm64 core binary: $(VLESS_CORE_ARM64_BIN) is older than $$dependency"; \
			echo "Rebuild it in ../vless-core-cli after changing OpenSSL: make ios-arm64"; \
			exit 1; \
		fi; \
	done
	@for dependency in "$(OPENSSL_IOS_SSL_LIB)" "$(OPENSSL_IOS_CRYPTO_LIB)"; do \
		if [ "$$dependency" -nt "$(VLESS_CORE_CURL_BIN)" ]; then \
			echo "Stale curl binary: $(VLESS_CORE_CURL_BIN) is older than $$dependency"; \
			echo "Rebuild it in ../vless-core-cli after changing OpenSSL: make curl-ios6"; \
			exit 1; \
		fi; \
	done
	@for dependency in "$(OPENSSL_IOS_ARM64_SSL_LIB)" "$(OPENSSL_IOS_ARM64_CRYPTO_LIB)"; do \
		if [ "$$dependency" -nt "$(VLESS_CORE_CURL_ARM64_BIN)" ]; then \
			echo "Stale arm64 curl binary: $(VLESS_CORE_CURL_ARM64_BIN) is older than $$dependency"; \
			echo "Rebuild it in ../vless-core-cli after changing OpenSSL: make curl-ios-arm64"; \
			exit 1; \
		fi; \
	done

$(BUILD_DIR)/zbar/%.o: $(ZBAR_DIR)/%.c $(ZBAR_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(ZBAR_CFLAGS) -c $< -o $@

$(ZBAR_LIB): check-ios-toolchain $(ZBAR_OBJ)
	$(IOS_AR) rcs $@ $(ZBAR_OBJ)
	$(IOS_RANLIB) $@

$(BUILD_DIR)/arm64/zbar/%.o: $(ZBAR_DIR)/%.c $(ZBAR_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(ZBAR_ARM64_CFLAGS) -c $< -o $@

$(ZBAR_ARM64_LIB): check-ios-toolchain $(ZBAR_ARM64_OBJ)
	$(IOS_AR) rcs $@ $(ZBAR_ARM64_OBJ)
	$(IOS_RANLIB) $@

$(BUILD_DIR)/app/%.o: %.m $(APP_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(APP_CFLAGS) -c $< -o $@

$(BUILD_DIR)/app/%.o: %.c $(APP_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(APP_CFLAGS) -c $< -o $@

$(BUILD_DIR)/arm64/app/%.o: %.m $(APP_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(APP_ARM64_CFLAGS) -c $< -o $@

$(BUILD_DIR)/arm64/app/%.o: %.c $(APP_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(APP_ARM64_CFLAGS) -c $< -o $@

$(APP_ARMV7_BIN): check-ios-toolchain $(APP_OBJ) $(ZBAR_LIB)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) -arch armv7 -miphoneos-version-min=6.0 -isysroot $(IOS_SDK) $(APP_OBJ) $(ZBAR_LIB) -o $@ $(APP_LDFLAGS)
	@$(IOS_OTOOL) -hv $@ | grep -qw PIE || (echo "Refusing non-PIE iOS binary: $@"; exit 1)

$(APP_ARM64_BIN): check-ios-toolchain $(APP_ARM64_OBJ) $(ZBAR_ARM64_LIB)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(APP_ARM64_CFLAGS) $(APP_ARM64_OBJ) $(ZBAR_ARM64_LIB) -o $@ $(APP_ARM64_LDFLAGS)
	@$(IOS_OTOOL) -hv $@ | grep -qw PIE || (echo "Refusing non-PIE iOS binary: $@"; exit 1)

$(DAEMON_ARMV7_BIN): check-ios-toolchain $(DAEMON_SRC) $(DAEMON_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(DAEMON_CFLAGS) $(DAEMON_SRC) -o $@ $(DAEMON_LDFLAGS)
	@$(IOS_OTOOL) -hv $@ | grep -qw PIE || (echo "Refusing non-PIE iOS binary: $@"; exit 1)

$(DAEMON_ARM64_BIN): check-ios-toolchain $(DAEMON_SRC) $(DAEMON_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(DAEMON_ARM64_CFLAGS) $(DAEMON_SRC) -o $@ $(DAEMON_ARM64_LDFLAGS)
	@$(IOS_OTOOL) -hv $@ | grep -qw PIE || (echo "Refusing non-PIE iOS binary: $@"; exit 1)

$(BOOTSTRAP_ARMV7_BIN): check-ios-toolchain $(BOOTSTRAP_SRC) $(DAEMON_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(DAEMON_CFLAGS) $(BOOTSTRAP_SRC) -o $@ $(DAEMON_LDFLAGS)
	@$(IOS_OTOOL) -hv $@ | grep -qw PIE || (echo "Refusing non-PIE iOS binary: $@"; exit 1)

$(BOOTSTRAP_ARM64_BIN): check-ios-toolchain $(BOOTSTRAP_SRC) $(DAEMON_HEADERS)
	mkdir -p $(dir $@)
	PATH="$(IOS_BIN):$$PATH" $(IOS_RUNTIME_ENV) $(IOS_CC) $(DAEMON_ARM64_CFLAGS) $(BOOTSTRAP_SRC) -o $@ $(BOOTSTRAP_ARM64_LDFLAGS)
	@$(IOS_OTOOL) -hv $@ | grep -qw PIE || (echo "Refusing non-PIE iOS binary: $@"; exit 1)

app: $(APP_ARMV7_BIN) $(APP_ARM64_BIN)

daemon: $(DAEMON_ARMV7_BIN) $(DAEMON_ARM64_BIN) $(BOOTSTRAP_ARMV7_BIN) $(BOOTSTRAP_ARM64_BIN)

package-root: check-package-inputs $(APP_ARMV7_BIN) $(APP_ARM64_BIN) $(DAEMON_ARMV7_BIN) $(DAEMON_ARM64_BIN) $(BOOTSTRAP_ARMV7_BIN) $(BOOTSTRAP_ARM64_BIN)
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
	cp app/icons/Default~iphone.png $(PKG_ROOT)/Applications/vless-core.app/Default~iphone.png
	cp app/icons/Default@2x~iphone.png $(PKG_ROOT)/Applications/vless-core.app/Default@2x~iphone.png
	cp app/icons/Default-568h@2x.png $(PKG_ROOT)/Applications/vless-core.app/Default-568h@2x.png
	cp app/icons/Default-Landscape@2x~ipad.png $(PKG_ROOT)/Applications/vless-core.app/Default-Landscape@2x~ipad.png
	cp app/icons/Default-Landscape~ipad.png $(PKG_ROOT)/Applications/vless-core.app/Default-Landscape~ipad.png
	cp app/icons/Default-Portrait@2x~ipad.png $(PKG_ROOT)/Applications/vless-core.app/Default-Portrait@2x~ipad.png
	cp app/icons/Default-Portrait~ipad.png $(PKG_ROOT)/Applications/vless-core.app/Default-Portrait~ipad.png
	cp app/icons/icon-refresh.png $(PKG_ROOT)/Applications/vless-core.app/icon-refresh.png
	cp app/icons/icon-terminal.png $(PKG_ROOT)/Applications/vless-core.app/icon-terminal.png
	cp app/icons/icon-list.png $(PKG_ROOT)/Applications/vless-core.app/icon-list.png
	cp app/icons/icon-settings.png $(PKG_ROOT)/Applications/vless-core.app/icon-settings.png
	cp app/icons/icon-trash.png $(PKG_ROOT)/Applications/vless-core.app/icon-trash.png
	cp app/icons/icon-ping.png $(PKG_ROOT)/Applications/vless-core.app/icon-ping.png
	cp app/icons/icon-flashlight.png $(PKG_ROOT)/Applications/vless-core.app/icon-flashlight.png
	cp app/icons/info.png $(PKG_ROOT)/Applications/vless-core.app/info.png
	cp app/icons/update-dark.png $(PKG_ROOT)/Applications/vless-core.app/update-dark.png
	cp app/icons/update-white.png $(PKG_ROOT)/Applications/vless-core.app/update-white.png
	cp $(ROOT)/LICENSE $(PKG_ROOT)/Applications/vless-core.app/LICENSE
	cp $(LEGAL_DIR)/THIRD_PARTY_LICENSES.txt $(PKG_ROOT)/Applications/vless-core.app/THIRD_PARTY_LICENSES.txt
	cp $(APP_ARMV7_BIN) $(PKG_ROOT)/Applications/vless-core.app/vless-core
	cp $(APP_ARM64_BIN) $(PKG_ROOT)/Applications/vless-core.app/vless-core-arm64
	cp $(DAEMON_ARMV7_BIN) $(PKG_ROOT)/usr/bin/vpnctld
	cp $(DAEMON_ARM64_BIN) $(PKG_ROOT)/usr/bin/vpnctld-arm64
	cp $(BOOTSTRAP_ARMV7_BIN) $(PKG_ROOT)/usr/bin/vpnctld-bootstrap
	cp $(BOOTSTRAP_ARM64_BIN) $(PKG_ROOT)/usr/bin/vpnctld-bootstrap-arm64
	cp $(VLESS_CORE_BIN) $(PKG_ROOT)/usr/bin/vless-core-darwin-armv7
	cp $(VLESS_CORE_ARM64_BIN) $(PKG_ROOT)/usr/bin/vless-core-darwin-arm64
	cp $(VLESS_CORE_CURL_BIN) $(PKG_ROOT)/usr/bin/vless-core-curl
	cp $(VLESS_CORE_CURL_ARM64_BIN) $(PKG_ROOT)/usr/bin/vless-core-curl-arm64
	cp $(REDSOCKS_BIN) $(PKG_ROOT)/usr/bin/redsocks-vless-core
	cp $(REDSOCKS_ARM64_BIN) $(PKG_ROOT)/usr/bin/redsocks-vless-core-arm64
	mkdir -p $(PKG_ROOT)/usr/share/vless-core
	cp $(CA_BUNDLE) $(PKG_ROOT)/usr/share/vless-core/cacert.pem
	if [ -f "$(OPENSSL_PATCH_STATUS_FILE)" ]; then \
		cp "$(OPENSSL_PATCH_STATUS_FILE)" $(PKG_ROOT)/usr/share/vless-core/openssl-patch-status; \
	else \
		printf '%s\n' unpatched > $(PKG_ROOT)/usr/share/vless-core/openssl-patch-status; \
	fi
	cp "$(OPENSSL_ARM64_PATCH_STATUS_FILE)" $(PKG_ROOT)/usr/share/vless-core/openssl-patch-status-arm64
	find $(PKG_ROOT) -type d -exec chmod 755 {} \;
	find $(PKG_ROOT) -type f -exec chmod 644 {} \;
	for binary in \
		$(PKG_ROOT)/Applications/vless-core.app/vless-core \
		$(PKG_ROOT)/Applications/vless-core.app/vless-core-arm64 \
		$(PKG_ROOT)/usr/bin/vpnctld \
		$(PKG_ROOT)/usr/bin/vpnctld-arm64 \
		$(PKG_ROOT)/usr/bin/vpnctld-bootstrap \
		$(PKG_ROOT)/usr/bin/vpnctld-bootstrap-arm64 \
		$(PKG_ROOT)/usr/bin/vless-core-darwin-armv7 \
		$(PKG_ROOT)/usr/bin/vless-core-darwin-arm64 \
		$(PKG_ROOT)/usr/bin/vless-core-curl \
		$(PKG_ROOT)/usr/bin/vless-core-curl-arm64 \
		$(PKG_ROOT)/usr/bin/redsocks-vless-core \
		$(PKG_ROOT)/usr/bin/redsocks-vless-core-arm64; do \
		chmod 755 "$$binary"; \
	done
	chmod 4755 $(PKG_ROOT)/usr/bin/vpnctld-bootstrap
	for script in preinst postinst prerm postrm; do \
		[ -f "$(PKG_ROOT)/DEBIAN/$$script" ] && chmod 755 "$(PKG_ROOT)/DEBIAN/$$script" || true; \
	done
	for binary in \
		$(PKG_ROOT)/Applications/vless-core.app/vless-core \
		$(PKG_ROOT)/usr/bin/vpnctld \
		$(PKG_ROOT)/usr/bin/vpnctld-bootstrap \
		$(PKG_ROOT)/usr/bin/vless-core-darwin-armv7 \
		$(PKG_ROOT)/usr/bin/vless-core-curl \
		$(PKG_ROOT)/usr/bin/redsocks-vless-core; do \
		$(LDID) -S "$$binary"; \
	done
	for binary in \
		$(PKG_ROOT)/usr/bin/vpnctld-bootstrap-arm64 \
		$(PKG_ROOT)/usr/bin/vless-core-darwin-arm64 \
		$(PKG_ROOT)/usr/bin/vless-core-curl-arm64 \
		$(PKG_ROOT)/usr/bin/redsocks-vless-core-arm64; do \
		$(LDID) -S "$$binary"; \
	done
	$(LDID) -S$(APP_ENTITLEMENTS) $(PKG_ROOT)/Applications/vless-core.app/vless-core-arm64
	$(LDID) -S$(DAEMON_ENTITLEMENTS) $(PKG_ROOT)/usr/bin/vpnctld-arm64
	chmod 4755 $(PKG_ROOT)/usr/bin/vpnctld-bootstrap

tarball: package-root
	cd $(BUILD_DIR) && tar -czf vless-core-app-bundle.tar.gz -C pkgroot .

deb: package-root
	rm -f $(BUILD_DIR)/com.vlesscore.app*_iphoneos-arm.deb
	dpkg-deb --uniform-compression -Zgzip -z6 --root-owner-group -b $(PKG_ROOT) $(DEB_OUT)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all app daemon check-ios-toolchain check-package-inputs package-root deb clean tarball
