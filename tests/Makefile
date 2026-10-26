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
APP_SOURCES := test_app_logic.m ../common/foundation_logic.m ../common/profile_logic.m ../common/secure_store.m ../common/connection_logic.m ../common/list_logic.m ../common/subscription_task.m ../integrations/incy/incy_links.m ../integrations/happ/happ_crypto.c
APP_OBJECTS := $(addprefix $(HOST_BUILD_DIR)/,$(patsubst ../%,%,$(APP_SOURCES:.m=.o)))
APP_OBJECTS := $(APP_OBJECTS:.c=.o)
APP_OBJECTS += $(HOST_BUILD_DIR)/core-parser/json.o
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
HOST_TESTS += $(HOST_BUILD_DIR)/test_flags
HOST_TESTS += $(HOST_BUILD_DIR)/test_flag_profiles
HOST_TESTS += $(HOST_BUILD_DIR)/test_runtime_uri
HOST_TESTS += $(HOST_BUILD_DIR)/test_incy
HOST_TESTS += $(HOST_BUILD_DIR)/test_httpupgrade_import
HOST_TESTS += $(HOST_BUILD_DIR)/test_main_state
HOST_TESTS += $(HOST_BUILD_DIR)/test_ping_batch
HOST_TESTS += $(HOST_BUILD_DIR)/test_main_ping
HOST_TESTS += $(HOST_BUILD_DIR)/test_main_network
HOST_TESTS += $(HOST_BUILD_DIR)/test_temp_probe
HOST_TESTS += $(HOST_BUILD_DIR)/test_temp_spawn $(HOST_BUILD_DIR)/test_probe_log
HOST_TESTS += $(HOST_BUILD_DIR)/test_main_images
HOST_TESTS += $(HOST_BUILD_DIR)/test_main_detail
HOST_TESTS += $(HOST_BUILD_DIR)/test_main_headers
HOST_TESTS += $(HOST_BUILD_DIR)/test_main_layout
HOST_TESTS += $(HOST_BUILD_DIR)/test_store_crypto
CORE_PARSE_SRC := uri utils xhttp_config xhttp_download xhttp_payload buffer_budget websocket grpc http_headers core_log
CORE_PARSE_SRC += vmess_uri shadowsocks_uri shadowsocks_crypto blake3 trojan core_random deadline socket_util relay_memory connection_trace resolver
CORE_PARSE_OBJ := $(addprefix $(HOST_BUILD_DIR)/core-parser/,$(addsuffix .o,$(CORE_PARSE_SRC)))
include $(ROOT)/common/zbar_sources.mk
HOST_ZBAR_OBJECTS := $(patsubst $(ZBAR_DIR)/%.c,$(HOST_BUILD_DIR)/zbar/%.o,$(ZBAR_SRC))
HOST_ZBAR_HEADERS := $(shell find $(ROOT)/$(ZBAR_DIR) -name '*.h')

test: requirements $(HOST_TESTS)
	$(HOST_BUILD_DIR)/test_app_logic
	$(HOST_BUILD_DIR)/test_main_state
	$(HOST_BUILD_DIR)/test_large_subscriptions
	$(HOST_BUILD_DIR)/test_flags
	$(HOST_BUILD_DIR)/test_flag_profiles 1000 scan
	python3 $(ROOT)/tests/test_flag_assets.py
	$(HOST_BUILD_DIR)/test_legacy_loopback_host
	$(HOST_BUILD_DIR)/test_legacy_dns_host
	$(HOST_BUILD_DIR)/test_main_geometry
	$(HOST_BUILD_DIR)/test_daemon_policy
	$(HOST_BUILD_DIR)/test_control_auth
	$(HOST_BUILD_DIR)/test_socket_peer
	$(HOST_BUILD_DIR)/test_system_proxy
	$(HOST_BUILD_DIR)/test_qr
	$(HOST_BUILD_DIR)/test_import_formats
	$(HOST_BUILD_DIR)/test_httpupgrade_import
	$(HOST_BUILD_DIR)/test_incy
	VC_HOST_BUILD_DIR="$(HOST_BUILD_DIR)" python3 $(ROOT)/tests/test_incy_loopback.py
	$(HOST_BUILD_DIR)/test_runtime_uri
	$(HOST_BUILD_DIR)/test_helper_monitor
	$(HOST_BUILD_DIR)/test_dns_relay
	$(HOST_BUILD_DIR)/test_ping
	$(HOST_BUILD_DIR)/test_ping_batch
	$(HOST_BUILD_DIR)/test_main_ping
	$(HOST_BUILD_DIR)/test_main_network
	$(HOST_BUILD_DIR)/test_temp_probe
	$(HOST_BUILD_DIR)/test_temp_spawn
	$(HOST_BUILD_DIR)/test_probe_log
	$(HOST_BUILD_DIR)/test_main_images
	$(HOST_BUILD_DIR)/test_main_detail
	$(HOST_BUILD_DIR)/test_main_headers
	$(HOST_BUILD_DIR)/test_main_layout
	$(HOST_BUILD_DIR)/test_store_crypto
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

$(HOST_BUILD_DIR)/integrations/incy/%.o: ../integrations/incy/%.m | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_app_logic: $(APP_OBJECTS)
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

UI_SOURCE_ROOT ?= $(ROOT)
$(HOST_BUILD_DIR)/main_state_save.inc: $(UI_SOURCE_ROOT)/app/main_state.m extract_ui_methods.py
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '- (void)saveData {' '?- (void)saveSettings {'

$(HOST_BUILD_DIR)/main_state_settings.inc: $(UI_SOURCE_ROOT)/app/main_settings.m extract_ui_methods.py
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:' '- (void)settingsVC:(SettingsVC *)vc didChangeAutomaticUpdateChecks:' '- (void)settingsVC:(SettingsVC *)vc didChangePreserveCustomSubscriptionNames:' '- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:' '- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:'

$(HOST_BUILD_DIR)/test_main_state.o: $(HOST_BUILD_DIR)/main_state_save.inc $(HOST_BUILD_DIR)/main_state_settings.inc
$(HOST_BUILD_DIR)/test_main_state.o: HOST_CPPFLAGS += -I$(HOST_BUILD_DIR)

$(HOST_BUILD_DIR)/test_main_state: $(HOST_BUILD_DIR)/test_main_state.o $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS))
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/test_large_subscriptions: $(HOST_BUILD_DIR)/test_large_subscriptions.o $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS))
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/test_flag_profiles: $(HOST_BUILD_DIR)/test_flag_profiles.o $(HOST_BUILD_DIR)/common/flag_logic.o $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS))
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/common/flag_logic.o: ../common/flag_logic.c ../common/flag_logic.h ../common/flag_data.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_ping: $(HOST_BUILD_DIR)/test_ping.o $(HOST_BUILD_DIR)/common/connection_logic.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS) -Wl,--wrap=kill,--wrap=waitpid,--wrap=select

$(HOST_BUILD_DIR)/test_ping_batch: $(HOST_BUILD_DIR)/test_ping_batch.o $(HOST_BUILD_DIR)/common/connection_logic.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/main_ping_test.inc: ../app/main_ping.m extract_ui_methods.py
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '- (void)pumpSubscriptionPings' '- (void)pingOperationFinished:' '- (BOOL)isURIInActiveSubscriptionPing:' '- (void)stopSubscriptionPingAtIndex:' '- (void)stopAllPings' '- (void)pingResultOnMain:' '?- (void)stopSubscriptionPingIdentifier:' '?- (void)prunePingStateForMetadata:'

$(HOST_BUILD_DIR)/test_main_ping.o: $(HOST_BUILD_DIR)/main_ping_test.inc
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -I$(HOST_BUILD_DIR) -MMD -MP -c test_main_ping.m -o $@

$(HOST_BUILD_DIR)/test_main_ping: $(HOST_BUILD_DIR)/test_main_ping.o $(HOST_BUILD_DIR)/common/connection_logic.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/main_network_test.inc: ../app/main_ping.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '- (void)refreshPingNetworkState' '- (NSDictionary *)pingOptionsForType:' '- (void)startPingForURI:' '- (void)startSubscriptionPingAtIndex:'

$(HOST_BUILD_DIR)/test_main_network.o: test_main_network.m $(HOST_BUILD_DIR)/main_network_test.inc
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -fblocks -I$(HOST_BUILD_DIR) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_main_network: $(HOST_BUILD_DIR)/test_main_network.o $(HOST_BUILD_DIR)/common/connection_logic.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ -L$(ROOT)/../toolchains/ios6/lib -Wl,-rpath,$(ROOT)/../toolchains/ios6/lib -lBlocksRuntime $(HOST_LIBS)

$(HOST_BUILD_DIR)/temp_probe_test.inc: ../app/network_ping.m extract_ui_methods.py
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ 'int ProxyGetViaTempCoreMs('

$(HOST_BUILD_DIR)/test_temp_probe.o: test_temp_probe.m $(HOST_BUILD_DIR)/temp_probe_test.inc
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -I$(HOST_BUILD_DIR) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_temp_probe: $(HOST_BUILD_DIR)/test_temp_probe.o $(HOST_BUILD_DIR)/common/connection_logic.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/temp_spawn_test.inc: ../app/network_ping.m extract_ui_methods.py
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ 'static pid_t spawn_temp_core_for_ping('

$(HOST_BUILD_DIR)/test_temp_spawn.o: test_temp_spawn.m $(HOST_BUILD_DIR)/temp_spawn_test.inc
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -I$(HOST_BUILD_DIR) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_temp_spawn: $(HOST_BUILD_DIR)/test_temp_spawn.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/test_probe_log: $(HOST_BUILD_DIR)/test_probe_log.o $(HOST_BUILD_DIR)/common/connection_logic.o
	$(HOST_CC) $(SANITIZE) $^ -o $@ -Wl,--wrap=pread $(HOST_LIBS)

$(HOST_BUILD_DIR)/main_header_images.inc: ../app/main_cells.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '?- (void)refreshHeaderImages'

$(HOST_BUILD_DIR)/test_main_images: test_main_images.m $(HOST_BUILD_DIR)/main_header_images.inc check.h
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -I$(HOST_BUILD_DIR) $< -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/main_detail_cache.inc: ../app/main_cells.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '?- (BOOL)hasDetailForURI:' '?- (void)rememberDetailURI:' '?- (BOOL)hasDetailLayoutForFrame:' '?- (void)rememberDetailLayoutForFrame:' '?- (void)invalidateDetailLayout' '?- (void)resetDetailState'

$(HOST_BUILD_DIR)/main_detail_apply.inc: ../app/main_table.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '?- (void)applyConfigDetailForURI:'

$(HOST_BUILD_DIR)/test_main_detail: test_main_detail.m $(HOST_BUILD_DIR)/main_detail_cache.inc $(HOST_BUILD_DIR)/main_detail_apply.inc check.h
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -I$(HOST_BUILD_DIR) $< -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/main_header_description.inc: ../app/main_cells.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '?- (void)updateDescriptionText:' '?- (CGFloat)descriptionHeightForWidth:' '?- (NSDictionary *)headerPresentationForInputs:' '?- (void)rememberHeaderPresentation:'

$(HOST_BUILD_DIR)/main_header_visible.inc: ../app/main_layout.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '- (void)refreshVisibleSubscriptionHeaderAccessories'

$(HOST_BUILD_DIR)/main_header_inputs.inc: ../app/main_layout.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '?static NSArray *VCHeaderPresentationInputs('

$(HOST_BUILD_DIR)/main_header_configure.inc: ../app/main_layout.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '- (void)configureSubscriptionHeaderCell:'

$(HOST_BUILD_DIR)/test_main_headers: test_main_headers.m $(HOST_BUILD_DIR)/main_header_description.inc $(HOST_BUILD_DIR)/main_header_visible.inc $(HOST_BUILD_DIR)/main_header_inputs.inc $(HOST_BUILD_DIR)/main_header_configure.inc check.h $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS))
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -I$(HOST_BUILD_DIR) $< $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS)) -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/main_phone_layout.inc: ../app/main_layout.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ '- (void)updatePhoneConnectionLayout'

$(HOST_BUILD_DIR)/test_main_layout: test_main_layout.m $(HOST_BUILD_DIR)/main_phone_layout.inc ../common/main_geometry.c check.h
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -I$(HOST_BUILD_DIR) $< ../common/main_geometry.c -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/store_encrypt.inc: ../common/foundation_logic.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ 'NSData *VCEncryptSecureStorePayload('

$(HOST_BUILD_DIR)/store_decrypt.inc: ../common/foundation_logic.m extract_ui_methods.py Makefile
	mkdir -p $(dir $@)
	python3 extract_ui_methods.py $< $@ 'NSData *VCDecryptSecureStorePayload('

$(HOST_BUILD_DIR)/test_store_crypto: test_store_crypto.m $(HOST_BUILD_DIR)/store_encrypt.inc $(HOST_BUILD_DIR)/store_decrypt.inc ../common/app_constants.h check.h
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -I$(HOST_BUILD_DIR) $< -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/app/proxy_probe.o: ../app/proxy_probe.m ../app/proxy_probe.h ../common/connection_logic.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_OBJCFLAGS) $(HOST_CFLAGS) -MMD -MP -c $< -o $@

$(HOST_BUILD_DIR)/test_proxy_probe: $(HOST_BUILD_DIR)/test_proxy_probe.o $(HOST_BUILD_DIR)/app/proxy_probe.o $(HOST_BUILD_DIR)/common/connection_logic.o $(HOST_BUILD_DIR)/common/subscription_task.o
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

$(HOST_BUILD_DIR)/test_flags: test_flags.c ../common/flag_logic.c ../common/flag_logic.h ../common/flag_data.h check.h | requirements
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CPPFLAGS) $(HOST_CFLAGS) test_flags.c ../common/flag_logic.c -o $@ $(SANITIZE)

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

$(HOST_BUILD_DIR)/test_runtime_uri: $(HOST_BUILD_DIR)/test_runtime_uri.o $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS)) $(CORE_PARSE_OBJ)
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/test_httpupgrade_import: $(HOST_BUILD_DIR)/test_httpupgrade_import.o $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS)) $(CORE_PARSE_OBJ)
	$(HOST_CC) $(SANITIZE) $^ -o $@ $(HOST_LIBS)

$(HOST_BUILD_DIR)/test_incy: $(HOST_BUILD_DIR)/test_incy.o $(filter-out $(HOST_BUILD_DIR)/test_app_logic.o,$(APP_OBJECTS))
	$(HOST_CC) $(SANITIZE) $^ -Wl,--wrap=EVP_CIPHER_CTX_new -Wl,--wrap=EVP_Digest -o $@ $(HOST_LIBS)

sanitizers:
	ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 $(MAKE) test HOST_BUILD_DIR=$(HOST_BUILD_DIR)-sanitized SANITIZE='-fsanitize=address,undefined -fno-omit-frame-pointer'

asan:
	ASAN_OPTIONS=detect_leaks=0 $(MAKE) test HOST_BUILD_DIR=$(HOST_BUILD_DIR)-asan SANITIZE='-fsanitize=address -fno-omit-frame-pointer'

-include $(APP_OBJECTS:.o=.d) $(CORE_PARSE_OBJ:.o=.d) $(HOST_BUILD_DIR)/test_ping.d $(HOST_BUILD_DIR)/test_proxy_probe.d $(HOST_BUILD_DIR)/app/proxy_probe.d $(HOST_BUILD_DIR)/test_import_formats.d $(HOST_BUILD_DIR)/test_httpupgrade_import.d $(HOST_BUILD_DIR)/test_runtime_uri.d $(HOST_BUILD_DIR)/test_incy.d $(HOST_BUILD_DIR)/test_large_subscriptions.d $(HOST_BUILD_DIR)/integrations/karing/karing_backup.d $(HOST_BUILD_DIR)/test_flag_profiles.d $(HOST_BUILD_DIR)/common/flag_logic.d $(HOST_BUILD_DIR)/test_main_state.d $(HOST_BUILD_DIR)/test_ping_batch.d $(HOST_BUILD_DIR)/test_main_ping.d
.PHONY: test requirements sanitizers asan
-include $(HOST_BUILD_DIR)/test_main_network.d
-include $(HOST_BUILD_DIR)/test_temp_probe.d $(HOST_BUILD_DIR)/test_temp_spawn.d $(HOST_BUILD_DIR)/test_probe_log.d
