ROOT := $(abspath ..)
HOST_BUILD_DIR ?= $(ROOT)/build/host-tests
HOST_CC ?= /usr/bin/clang
HOST_PREFIX ?= $(if $(wildcard $(ROOT)/../toolchains/host-tests/usr/include/GNUstep/Foundation/Foundation.h),$(abspath $(ROOT)/../toolchains/host-tests),)
GNUSTEP_CONFIG ?= gnustep-config
HOST_CPPFLAGS := -I$(ROOT)/tests/support -I$(ROOT)/tests -I$(ROOT)/common -I$(shell gcc -print-file-name=include)
ifneq ($(HOST_PREFIX),)
HOST_CPPFLAGS += -I$(HOST_PREFIX)/usr/include/GNUstep -I$(HOST_PREFIX)/usr/include
HOST_OBJCFLAGS := -DGNUSTEP -DGNUSTEP_BASE_LIBRARY=1 -DGNU_RUNTIME=1 -fconstant-string-class=NSConstantString -fobjc-exceptions -pthread
HOST_LIBS := -L$(HOST_PREFIX)/usr/lib -L$(HOST_PREFIX)/usr/lib/$(shell gcc -dumpmachine) -lgnustep-base -lobjc -lsqlite3 -lcrypto -lz -lm -pthread
else
HOST_OBJCFLAGS := $(shell $(GNUSTEP_CONFIG) --objc-flags 2>/dev/null)
HOST_LIBS := $(shell $(GNUSTEP_CONFIG) --base-libs 2>/dev/null) -lsqlite3 -lcrypto -lz -lm
endif
HOST_CFLAGS := -O1 -g -Wall -Wextra -Wno-unused-const-variable -Wno-incompatible-pointer-types $(SANITIZE)
APP_SOURCES := test_app_logic.m ../common/foundation_logic.m ../common/profile_logic.m ../common/secure_store.m ../common/connection_logic.m ../common/list_logic.m ../integrations/happ/happ_crypto.c
APP_OBJECTS := $(addprefix $(HOST_BUILD_DIR)/,$(patsubst ../%,%,$(APP_SOURCES:.m=.o)))
APP_OBJECTS := $(APP_OBJECTS:.c=.o)
HOST_TESTS := $(HOST_BUILD_DIR)/test_app_logic $(HOST_BUILD_DIR)/test_legacy_loopback_host $(HOST_BUILD_DIR)/test_legacy_dns_host
HOST_TESTS += $(HOST_BUILD_DIR)/test_main_geometry $(HOST_BUILD_DIR)/test_daemon_policy
HOST_TESTS += $(HOST_BUILD_DIR)/test_control_auth $(HOST_BUILD_DIR)/test_socket_peer
HOST_TESTS += $(HOST_BUILD_DIR)/test_system_proxy
HOST_TESTS += $(HOST_BUILD_DIR)/test_qr $(HOST_BUILD_DIR)/test_import_formats
HOST_TESTS += $(HOST_BUILD_DIR)/test_helper_monitor
HOST_TESTS += $(HOST_BUILD_DIR)/test_dns_relay
HOST_TESTS += $(HOST_BUILD_DIR)/test_ping
HOST_TESTS += $(HOST_BUILD_DIR)/test_proxy_probe
HOST_TESTS += $(HOST_BUILD_DIR)/test_core_config
HOST_TESTS += $(HOST_BUILD_DIR)/test_large_subscriptions
CORE_PARSE_SRC := uri utils xhttp_config xhttp_download xhttp_payload buffer_budget websocket grpc http_headers json core_log
CORE_PARSE_SRC += vmess_uri shadowsocks_uri shadowsocks_crypto blake3 trojan core_random deadline socket_util relay_memory connection_trace resolver
CORE_PARSE_OBJ := $(addprefix $(HOST_BUILD_DIR)/core-parser/,$(addsuffix .o,$(CORE_PARSE_SRC)))
include $(ROOT)/common/zbar_sources.mk
HOST_ZBAR_OBJECTS := $(patsubst $(ZBAR_DIR)/%.c,$(HOST_BUILD_DIR)/zbar/%.o,$(ZBAR_SRC))
HOST_ZBAR_HEADERS := $(shell find $(ROOT)/$(ZBAR_DIR) -name '*.h')

test: requirements $(HOST_TESTS)
	$(HOST_BUILD_DIR)/test_app_logic
	$(HOST_BUILD_DIR)/test_large_subscriptions
	$(HOST_BUILD_DIR)/test_legacy_loopback_host
	$(HOST_BUILD_DIR)/test_legacy_dns_host
	$(HOST_BUILD_DIR)/test_main_geometry
	$(HOST_BUILD_DIR)/test_daemon_policy
	$(HOST_BUILD_DIR)/test_control_auth
	$(HOST_BUILD_DIR)/test_socket_peer
	$(HOST_BUILD_DIR)/test_system_proxy
	$(HOST_BUILD_DIR)/test_qr
	$(HOST_BUILD_DIR)/test_import_formats
	$(HOST_BUILD_DIR)/test_helper_monitor
	$(HOST_BUILD_DIR)/test_dns_relay
	$(HOST_BUILD_DIR)/test_ping
	$(HOST_BUILD_DIR)/test_proxy_probe
	$(HOST_BUILD_DIR)/test_core_config
	VC_HOST_BUILD_DIR="$(HOST_BUILD_DIR)" VC_TEST_SANITIZE="$(SANITIZE)" python3 $(ROOT)/tests/test_core_bridge.py
	python3 $(ROOT)/tests/test_app_structure.py
	python3 $(ROOT)/tests/test_package.py
	python3 $(ROOT)/tests/test_preflight.py

requirements:
	@test -x "$(HOST_CC)" || { echo 'Missing host compiler: install clang or set HOST_CC.' >&2; exit 1; }
	@if [ -z "$(HOST_PREFIX)" ]; then command -v "$(GNUSTEP_CONFIG)" >/dev/null || { echo 'Missing GNUstep development headers: install libgnustep-base-dev and gnustep-make, or set HOST_PREFIX. make never installs packages.' >&2; exit 1; }; fi
	@printf '%s\n' '#import <Foundation/Foundation.h>' '#include <sqlite3.h>' '#include <openssl/evp.h>' '#include <zlib.h>' | $(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) -x objective-c -fsyntax-only - >/dev/null || { echo 'Missing host development dependencies: libgnustep-base-dev, libobjc-dev, libsqlite3-dev, libssl-dev, zlib1g-dev.' >&2; exit 1; }

$(HOST_BUILD_DIR)/%.o: %.m | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/%.o: %.c | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/common/%.o: ../common/%.m | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/integrations/happ/%.o: ../integrations/happ/%.c | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_app_logic: $(APP_OBJECTS)
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/test_large_subscriptions: $(HOST_BUILD_DIR)/test_large_subscriptions.o $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS))
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/test_ping: $(HOST_BUILD_DIR)/test_ping.o $(HOST_BUILD_DIR)/common/connection_logic.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS) -Wl,--wrap=kill,--wrap=waitpid,--wrap=select

$(HOST_BUILD_DIR)/app/proxy_probe.o: ../app/proxy_probe.m ../app/proxy_probe.h ../common/connection_logic.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_proxy_probe: $(HOST_BUILD_DIR)/test_proxy_probe.o $(HOST_BUILD_DIR)/app/proxy_probe.o $(HOST_BUILD_DIR)/common/connection_logic.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS) -Wl,--wrap=socket,--wrap=write,--wrap=read

$(HOST_BUILD_DIR)/test_legacy_loopback_host: test_legacy_loopback_host.c legacy_loopback_test.c ../daemon/legacy_loopback.c ../daemon/legacy_loopback.h support/darwin_route.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) $< -o $@ $(SANITIZE)

$(HOST_BUILD_DIR)/test_legacy_dns_host: test_legacy_dns_host.m legacy_dns_test.c ../daemon/legacy_dns.c ../daemon/legacy_dns.h support/CoreFoundation/CoreFoundation.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) $< -o $@ $(HOST_LIBS) $(SANITIZE)

$(HOST_BUILD_DIR)/test_main_geometry: test_main_geometry.c ../common/main_geometry.c ../common/main_geometry.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) test_main_geometry.c ../common/main_geometry.c -o $@ -lm $(SANITIZE)

$(HOST_BUILD_DIR)/test_daemon_policy: test_daemon_policy.c ../common/daemon_policy.c ../common/daemon_policy.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) test_daemon_policy.c ../common/daemon_policy.c -o $@ -lcrypto $(SANITIZE)

$(HOST_BUILD_DIR)/test_control_auth: test_control_auth.c ../common/control_auth.c ../common/control_auth.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) test_control_auth.c ../common/control_auth.c -o $@ $(SANITIZE)

$(HOST_BUILD_DIR)/test_helper_monitor: test_helper_monitor.c ../common/helper_monitor.c ../common/helper_monitor.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) test_helper_monitor.c ../common/helper_monitor.c -o $@ $(SANITIZE)

$(HOST_BUILD_DIR)/test_dns_relay: test_dns_relay.c ../common/dns_relay.c ../common/dns_relay.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) test_dns_relay.c ../common/dns_relay.c -o $@ -pthread $(SANITIZE)

$(HOST_BUILD_DIR)/test_socket_peer: test_socket_peer.c ../daemon/socket_peer_pid.c ../daemon/socket_peer_pid.h support/darwin_peer.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) test_socket_peer.c -o $@ $(SANITIZE)

$(HOST_BUILD_DIR)/test_system_proxy: test_system_proxy.m ../daemon/system_proxy.c ../daemon/system_proxy.h support/CoreFoundation/CoreFoundation.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) test_system_proxy.m -o $@ $(HOST_LIBS) $(SANITIZE)

$(HOST_BUILD_DIR)/zbar/%.o: $(ROOT)/$(ZBAR_DIR)/%.c $(HOST_ZBAR_HEADERS) | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) -O1 -g -w -I$(ROOT)/$(ZBAR_DIR) $(SANITIZE) -c $< -o $@

$(HOST_BUILD_DIR)/test_qr: test_qr.c check.h $(HOST_ZBAR_OBJECTS) | requirements
	$(HOST_CC) $(HOST_CFLAGS) -I$(ROOT)/$(ZBAR_DIR) test_qr.c $(HOST_ZBAR_OBJECTS) -o $@ $(SANITIZE)

$(HOST_BUILD_DIR)/integrations/karing/%.o: ../integrations/karing/%.m | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_core_config: test_core_config.c ../daemon/core_config.c ../daemon/core_config.h ../common/daemon_policy.c ../common/daemon_policy.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CFLAGS) test_core_config.c ../daemon/core_config.c ../common/daemon_policy.c -o $@ $(SANITIZE)

$(HOST_BUILD_DIR)/core-parser/%.o: ../../vless-core-cli/src/%.c | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CFLAGS) -I$(ROOT)/../vless-core-cli/include -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_import_formats: $(HOST_BUILD_DIR)/test_import_formats.o $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS)) $(HOST_BUILD_DIR)/integrations/karing/karing_backup.o $(CORE_PARSE_OBJ)
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

sanitizers:
	ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 $(MAKE) test HOST_BUILD_DIR=$(HOST_BUILD_DIR)-sanitized SANITIZE='-fsanitize=address,undefined -fno-omit-frame-pointer'

asan:
	ASAN_OPTIONS=detect_leaks=0 $(MAKE) test HOST_BUILD_DIR=$(HOST_BUILD_DIR)-asan SANITIZE='-fsanitize=address -fno-omit-frame-pointer'

-include $(APP_OBJECTS:.o=.d) $(CORE_PARSE_OBJ:.o=.d) $(HOST_BUILD_DIR)/test_ping.d $(HOST_BUILD_DIR)/test_proxy_probe.d $(HOST_BUILD_DIR)/app/proxy_probe.d $(HOST_BUILD_DIR)/test_import_formats.d $(HOST_BUILD_DIR)/integrations/karing/karing_backup.d
.PHONY: test requirements sanitizers asan
