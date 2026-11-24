#include "../daemon/diagnostic_report.h"
#include "../daemon/vpnctld_protocol.h"
#include "check.h"
#include <string.h>

int main(void) {
    char output[4096];
    CHECK("report/log-encodes-line-boundaries", VCDiagnosticEncodeLog("END\nSECTION events\nDONE\n", 24, output, sizeof(output)) == 0 &&
          !strcmp(output, "RU5EClNFQ1RJT04gZXZlbnRzCkRPTkUK"));
    CHECK("report/log-encodes-binary", VCDiagnosticEncodeLog("\0\377", 2, output, 5) == 0 && !strcmp(output, "AP8="));
    CHECK("report/log-padding", VCDiagnosticEncodeLog("x", 1, output, 5) == 0 && !strcmp(output, "eA=="));
    CHECK("report/log-output-bound", VCDiagnosticEncodeLog("x", 1, output, 4) != 0);
    char log_tail[VC_DIAGNOSTIC_LOG_TAIL_BYTES]={0}, encoded[VC_DIAGNOSTIC_LOG_BASE64_BYTES + 1];
    CHECK("report/log-maximum-tail", VCDiagnosticEncodeLog(log_tail, sizeof(log_tail), encoded, sizeof(encoded)) == 0 &&
          strlen(encoded) == VC_DIAGNOSTIC_LOG_BASE64_BYTES);

    VCDiagnosticPFNames names = {0};
    VCDiagnosticPFText(&names, "nat on en0 inet proto tcp from any to ! <other_secret> -> 127.0.0.1\n"
                               "rdr pass on lo0 inet proto tcp from any to ! <other_secret> -> 127.0.0.1 port 10809\n"
                               "rdr-anchor \"vlesscore\"\n", output, sizeof(output));
    CHECK("report/nat-shape", strstr(output, "nat on en0 inet proto tcp from any to ! <table#1> -> endpoint#2"));
    CHECK("report/rdr-local-port", strstr(output, "rdr pass on lo0 inet proto tcp from any to ! <table#1> -> endpoint#2 port 10809"));
    CHECK("report/anchor-own-name", strstr(output, "rdr-anchor \"vlesscore\""));
    VCDiagnosticPFText(&names, "pass out quick on en0 route-to (lo0 127.0.0.1) inet6 from 2001:db8::1/64 to <other_secret> port = 443 label \"vless://password with spaces\"\n",
                       output, sizeof(output));
    CHECK("report/filter-shape", strstr(output, "route-to (lo0 endpoint#2) inet6 from endpoint#3 to <table#1> port = 443"));
    CHECK("report/no-raw-pf-values", !strstr(output, "secret") && !strstr(output, "password") && !strstr(output, "2001:"));
    CHECK("report/no-rule-output", !strcmp(VCDiagnosticPFText(&names, "", output, sizeof(output)), "(empty)"));
    CHECK("report/pf-output-bound", !strcmp(VCDiagnosticPFText(&names, "pass out quick on en0\n", output, 8), "(output limit exceeded)"));
    FINISH("diagnostic report redaction");
}
