#define _DEFAULT_SOURCE 1
#include "../common/daemon_policy.h"
#include "check.h"
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <openssl/evp.h>

static const char *baselineRuleDigests[16] = {
    "ced8c1e2ee63dd66b7159a0b6fb4aa48d73e9db3a1881e1f165320dd7fb93a4a",
    "cf994b0f3a6c62c72e90e4660ef4a94d5052fd1289d56022d412284e05203eb4",
    "349f6f21c8870f463951d6a8b94ff3b7841e13d3c44936fc555c1e400d65cafc",
    "de5c1005fec8e050827fc2d12b414c5c0a1c129e897e59447b0ef344f5c1e9af",
    "756a4c0d6ef7f3a5d037ceebe7c196bd66f66609c18e4a9ab2f36075bd95f3e7",
    "a8c80bb0d23736381f786cf4901d3ebfb77e1b51f450ca854d478418628a8ef1",
    "45eaca65dea7a60c045c84b7fa3216ce3a0168745f801b4f9d1fe953becddd2c",
    "0a61e74591ebf35823fc8a6528d987946ba57e486f3da3183bfb5d7f4f7ee224",
    "d1cca5707d635e1a88eae1bda7c80021ab15de266d90d6c249e420b41400e461",
    "6c1cad2950e5fafd4aa8a218225693083398cad33623b78b45a540e133786aba",
    "c859283051f7c7bfd8720bfb673b8e64f17895f4f09c3038bfa320b8c3841afc",
    "91f64d0d26d9ee248ca2a2b21801451b619b0b4b79d0e32cabb5ace296619798",
    "2c919ee9ded2fe30d927bcaebcfb67e153f72bc09986e567bb99d63e15122126",
    "d1d14bb494e08ed5e646a6e3f4272eabc15aa2867a93b628e2cb6673046751ca",
    "aa6893d42d7bbd843ac8d30d40517ceb14aec7961e813fb28abcd0d80e0640e6",
    "8370bbc764d159d39cb04f2f191ab7fa506b1781a9144e27ce9fe9b33a937061",
};

int main(void) {
    char host[128], list[128] = ""; int bypass = 0;
    CHECK("daemon/host-vless", parse_server_host("vless://uuid@example.test:443?type=tcp", host, sizeof(host)) == 0 && !strcmp(host, "example.test"));
    CHECK("daemon/host-socks-auth-ipv6", parse_server_host("socks5://u:p@[2001:db8::1]:1080", host, sizeof(host)) == 0 && !strcmp(host, "2001:db8::1"));
    for (const char **scheme=(const char *[]){"vless://", "socks5://", "trojan://", "vmess://", "ss://", NULL}; *scheme; scheme++)
        CHECK("daemon/current-core-schemes",is_supported_config_uri(*scheme));
    CHECK("daemon/unsupported-scheme", !is_supported_config_uri("http://example.test"));
    CHECK("daemon/ip-list-add", !ip_list_append(list, sizeof(list), "203.0.113.1"));
    CHECK("daemon/ip-list-dedup", !ip_list_append(list, sizeof(list), "203.0.113.1") && !strcmp(list, "203.0.113.1"));
    CHECK("daemon/ip-list-overflow", ip_list_append(list, 3, "203.0.113.2") == -1);
    CHECK("routing/valid-payload", routing_payload_valid_with_capacity("1;direct;1;domain:example.test:proxy", &bypass, 8192) && bypass);
    CHECK("routing/invalid-shell-content", !routing_payload_valid_with_capacity("1;proxy;1;$(id)", &bypass, 8192));
    CHECK("routing/invalid-action", !routing_payload_valid_with_capacity("1;bad;1", &bypass, 8192));
    CHECK("routing/invalid-lan-flag", !routing_payload_valid_with_capacity("1;proxy;2", &bypass, 8192));
    CHECK("routing/payload-overflow", !routing_payload_valid_with_capacity("0;proxy;1", &bypass, 3));
    CHECK("routing/lan-bypass-on", ipv4_is_permanent_bypass_for_policy("192.168.1.3", "203.0.113.1", 1));
    CHECK("routing/lan-bypass-off", !ipv4_is_permanent_bypass_for_policy("192.168.1.3", "203.0.113.1", 0));
    CHECK("routing/server-always-bypassed", ipv4_is_permanent_bypass_for_policy("203.0.113.1", "203.0.113.1", 0));
    CHECK("routing/loopback-always-bypassed", ipv4_is_permanent_bypass_for_policy("127.0.0.1", "203.0.113.1", 0));
    CHECK("pf/own-dispatch-recognized", pf_dispatch_rules_only("nat-anchor \"vlesscore\"\nrdr-anchor \"vlesscore\"\n", 1));
    CHECK("pf/foreign-rules-not-ours", !pf_dispatch_rules_only("nat-anchor \"vlesscore\"\nrdr-anchor \"vlesscore\"\npass all\n", 1));
    CHECK("pf/duplicate-anchor-not-ours", !pf_dispatch_rules_only("anchor \"vlesscore\"\nanchor \"vlesscore\"\n", 0));
    CHECK("pf/interface-injection-rejected", !ifname_is_safe("en0;touch /tmp/x"));
    CHECK("pf/wifi-cellular-allowed", pf_interface_allowed("en0") && pf_interface_allowed("pdp_ip0") && !pf_interface_allowed("lo0"));
    char directory[] = "/tmp/vless-host-pf.XXXXXX"; CHECK("pf/private-test-directory", mkdtemp(directory) != NULL);
    char path[256]; snprintf(path, sizeof(path), "%s/pf.conf", directory);
    char interfaces[][32] = {"en0", "pdp_ip0"};
    for (int mode = 0; mode <= 7; mode++) for (int lan = 0; lan < 2; lan++) {
        CHECK("pf/generate-every-rule-mode", vc_write_pf_conf(path, lan, "203.0.113.1, 198.51.100.2", interfaces, 2, 12080, 12530, mode) == 0);
        FILE *file = fopen(path, "r"); CHECK("pf/read-generated-rules", file != NULL);
        char text[16384]; size_t size = fread(text, 1, sizeof(text) - 1, file); text[size] = 0; fclose(file);
        unsigned char digest[32]; unsigned length = 0;
        CHECK("pf/hash-generated-rule-text", EVP_Digest(text, size, digest, &length, EVP_sha256(), NULL) && length == 32);
        char digestText[65], scenario[80];
        for (unsigned i = 0; i < length; i++) snprintf(digestText + i * 2, 3, "%02x", digest[i]);
        snprintf(scenario, sizeof(scenario), "pf/full-baseline-text/mode%d/lan%d", mode, lan);
        CHECK(scenario, strcmp(digestText, baselineRuleDigests[mode * 2 + lan]) == 0);
        CHECK("pf/upstream-bypass-present", strstr(text, "203.0.113.1, 198.51.100.2") != NULL);
        CHECK("pf/tcp-redirect-port", strstr(text, "12080") != NULL);
        CHECK("pf/dns-redirect-port", strstr(text, "12530") != NULL);
        CHECK("pf/udp-leak-block", strstr(text, "proto udp from any to ! <vlesscore_bypass>") != NULL);
        CHECK("pf/ipv6-leak-block", strstr(text, "inet6 all") != NULL);
        CHECK("pf/lan-policy-respected", (strstr(text, "192.168.0.0/16") != NULL) == lan);
    }
    CHECK("pf/no-empty-server-list", vc_write_pf_conf(path, 1, "", interfaces, 2, 12080, 12530, 0) == -1);
    CHECK("pf/no-empty-interface-list", vc_write_pf_conf(path, 1, "203.0.113.1", interfaces, 0, 12080, 12530, 0) == -1);
    CHECK("pf/cleanup-fixture", !unlink(path) && !rmdir(directory)); FINISH("daemon policy"); return 0;
}
