#import "app_support.h"

static void CleanupSubscriptionFetchTempFiles(const char *out_path, const char *err_path, const char *hdr_path) {
    if (out_path && *out_path) unlink(out_path);
    if (err_path && *err_path) unlink(err_path);
    if (hdr_path && *hdr_path) unlink(hdr_path);
}

static int CreateCurlURLConfigFD(const char *url) {
    if (!url || !*url) return -1;
    size_t urlLength = strlen(url);
    if (urlLength > kVCMaximumSubscriptionURLBytes || urlLength > (SIZE_MAX - 16) / 2) return -1;

    size_t capacity = urlLength * 2 + 16;
    char *config = (char *)malloc(capacity);
    if (!config) return -1;

    size_t used = 0;
    memcpy(config + used, "url = \"", 7);
    used += 7;
    for (size_t i = 0; i < urlLength; i++) {
        unsigned char value = (unsigned char)url[i];
        if (value < 0x20 || value == 0x7f) {
            memset(config, 0, capacity);
            free(config);
            return -1;
        }
        if (value == '\\' || value == '"') config[used++] = '\\';
        config[used++] = (char)value;
    }
    config[used++] = '"';
    config[used++] = '\n';

    char path[] = "/tmp/vlesscore-curl-url-XXXXXX";
    int fd = mkstemp(path);
    if (fd >= 0) unlink(path);
    BOOL ok = fd >= 0 && fchmod(fd, 0600) == 0 &&
              VCWriteAllToFileDescriptor(fd, config, used) && lseek(fd, 0, SEEK_SET) == 0;
    memset(config, 0, capacity);
    free(config);
    if (!ok) {
        if (fd >= 0) close(fd);
        return -1;
    }
    return fd;
}

NSData *FetchURLViaVlessCoreCurl(NSString *urlString,
                                       BOOL allowInsecureFetch,
                                       BOOL allowPlainHTTP,
                                       BOOL useHappHeaders,
                                       BOOL sendSubscriptionHWID,
                                       NSString *userAgent,
                                       NSString **errOut,
                                       NSString **headersOut,
                                       int *exitCodeOut) {
    const char *curl_path = "/usr/bin/vless-core-curl";
    const char *ca_bundle_path = "/usr/share/vless-core/cacert.pem";

    if (errOut) *errOut = nil;
    if (headersOut) *headersOut = nil;
    if (exitCodeOut) *exitCodeOut = -1;
    VCSubscriptionTask *task=VCCurrentSubscriptionTask();
    if (task.isCancelled) { if (errOut) *errOut=task.cancellationReason; return nil; }
    [task setPhase:@"Downloading"];

    if (!urlString || [urlString length] == 0) {
        if (errOut) *errOut = @"Invalid subscription URL";
        return nil;
    }

    if (access(curl_path, X_OK) != 0) {
        if (errOut) *errOut = @"vless-core-curl not found";
        return nil;
    }

    NSURL *parsedURL = [NSURL URLWithString:urlString];
    NSString *scheme = [[[parsedURL scheme] lowercaseString] copy];
    BOOL usesHTTPS = [scheme isEqualToString:@"https"];
    BOOL usesHTTP = [scheme isEqualToString:@"http"];
    BOOL allowsHTTPTransport = usesHTTP || useHappHeaders;
    if ((!usesHTTPS && !usesHTTP) || ![[parsedURL host] length]) {
        [scheme release];
        if (errOut) *errOut = @"Subscription URL must use HTTP or HTTPS";
        return nil;
    }
    if (usesHTTP && !allowPlainHTTP && !useHappHeaders) {
        [scheme release];
        if (errOut) *errOut = @"Plain HTTP subscription requires confirmation";
        return nil;
    }
    [scheme release];

    const char *url_c = [urlString UTF8String];
    if (!url_c || !*url_c) {
        if (errOut) *errOut = @"Invalid subscription URL";
        return nil;
    }
    const char *user_agent_c = ([userAgent length] > 0) ? [userAgent UTF8String] : NULL;

    NSString *hwid = sendSubscriptionHWID ? TrimSimpleString(SubscriptionHWID()) : nil;
    char hwid_header[256];
    memset(hwid_header, 0, sizeof(hwid_header));
    const char *hwid_c = [hwid UTF8String];
    if (hwid_c && *hwid_c) {
        snprintf(hwid_header, sizeof(hwid_header), "X-HWID: %s", hwid_c);
    }

    char happ_locale_header[256];
    char device_os_header[64];
    char device_os_version_header[128];
    char device_model_header[256];
    memset(happ_locale_header, 0, sizeof(happ_locale_header));
    memset(device_os_header, 0, sizeof(device_os_header));
    memset(device_os_version_header, 0, sizeof(device_os_version_header));
    memset(device_model_header, 0, sizeof(device_model_header));
    if (sendSubscriptionHWID || useHappHeaders) {
        UIDevice *device = [UIDevice currentDevice];
        NSString *systemVersion = TrimSimpleString([device systemVersion]);
        NSString *model = DeviceModelName();
        const char *system_version_c = [systemVersion UTF8String];
        const char *model_c = [model UTF8String];
        snprintf(device_os_header, sizeof(device_os_header), "%s", "X-Device-OS: iOS");
        if (system_version_c && *system_version_c) {
            snprintf(device_os_version_header, sizeof(device_os_version_header), "X-Ver-OS: %s", system_version_c);
        }
        if (model_c && *model_c) {
            snprintf(device_model_header, sizeof(device_model_header), "X-Device-Model: %s", model_c);
        }
        if (useHappHeaders) {
            NSString *locale = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
            const char *locale_c = [locale UTF8String];
            if (locale_c && *locale_c) {
                snprintf(happ_locale_header, sizeof(happ_locale_header), "X-Device-Locale: %s", locale_c);
            }
        }
    }

    char out_tmpl[] = "/tmp/vlesscore-sub-out-XXXXXX";
    int out_fd = mkstemp(out_tmpl);
    if (out_fd < 0) {
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(out) failed: %s", strerror(errno)];
        return nil;
    }

    char err_tmpl[] = "/tmp/vlesscore-sub-err-XXXXXX";
    int err_fd = mkstemp(err_tmpl);
    if (err_fd < 0) {
        close(out_fd);
        CleanupSubscriptionFetchTempFiles(out_tmpl, NULL, NULL);
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(err) failed: %s", strerror(errno)];
        return nil;
    }

    char hdr_tmpl[] = "/tmp/vlesscore-sub-hdr-XXXXXX";
    int hdr_fd = mkstemp(hdr_tmpl);
    if (hdr_fd < 0) {
        close(out_fd);
        close(err_fd);
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, NULL);
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(hdr) failed: %s", strerror(errno)];
        return nil;
    }
    close(hdr_fd);

    int curl_config_fd = -1;
    if (!useHappHeaders) {
        curl_config_fd = CreateCurlURLConfigFD(url_c);
        if (curl_config_fd < 0) {
            close(out_fd);
            close(err_fd);
            CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
            if (errOut) *errOut = @"Invalid or excessively long subscription URL";
            return nil;
        }
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(out_fd);
        close(err_fd);
        if (curl_config_fd >= 0) close(curl_config_fd);
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        if (errOut) *errOut = [NSString stringWithFormat:@"fork failed: %s", strerror(errno)];
        return nil;
    }

    if (pid == 0) {
        if (curl_config_fd >= 0) {
            if (curl_config_fd != STDIN_FILENO) {
                if (dup2(curl_config_fd, STDIN_FILENO) < 0) _exit(126);
                close(curl_config_fd);
            }
        } else {
            int dn = open("/dev/null", O_RDONLY);
            if (dn >= 0) {
                (void)dup2(dn, STDIN_FILENO);
                if (dn > STDERR_FILENO) close(dn);
            }
        }

        (void)dup2(out_fd, STDOUT_FILENO);
        (void)dup2(err_fd, STDERR_FILENO);
        close(out_fd);
        close(err_fd);

        char *argv[48];
        int argc = 0;
        argv[argc++] = (char *)"vless-core-curl";
        argv[argc++] = (char *)"--fail";
        argv[argc++] = (char *)"--location";
        argv[argc++] = (char *)"--compressed";
        argv[argc++] = (char *)"--silent";
        argv[argc++] = (char *)"--show-error";
        if (!useHappHeaders) {
            argv[argc++] = (char *)"--config";
            argv[argc++] = (char *)"-";
        }
        argv[argc++] = (char *)"--connect-timeout";
        argv[argc++] = (char *)"10";
        argv[argc++] = (char *)"--max-time";
        argv[argc++] = (char *)"25";
        argv[argc++] = (char *)"--max-filesize";
        argv[argc++] = (char *)"33554432";
        argv[argc++] = (char *)"--max-redirs";
        argv[argc++] = (char *)"10";
        argv[argc++] = (char *)"--proto";
        argv[argc++] = (char *)(allowsHTTPTransport ? "=https,http" : "=https");
        argv[argc++] = (char *)"--proto-redir";
        argv[argc++] = (char *)(allowsHTTPTransport ? "=https,http" : "=https");
        argv[argc++] = (char *)"--curves";
        argv[argc++] = (char *)"X25519:P-256:P-384";
        argv[argc++] = (char *)"-D";
        argv[argc++] = hdr_tmpl;

        if (useHappHeaders) {
            argv[argc++] = (char *)"--user-agent";
            argv[argc++] = (char *)[kHappSubscriptionUserAgent UTF8String];
            if (happ_locale_header[0] != '\0') {
                argv[argc++] = (char *)"-H";
                argv[argc++] = happ_locale_header;
            }
        } else if (user_agent_c && *user_agent_c) {
            argv[argc++] = (char *)"--user-agent";
            argv[argc++] = (char *)user_agent_c;
        }

        if (device_os_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = device_os_header;
        }
        if (device_os_version_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = device_os_version_header;
        }
        if (device_model_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = device_model_header;
        }

        if (allowInsecureFetch) {
            argv[argc++] = (char *)"--insecure";
        }

        if (sendSubscriptionHWID && hwid_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = hwid_header;
        }

        if (!allowInsecureFetch && access(ca_bundle_path, R_OK) == 0) {
            argv[argc++] = (char *)"--cacert";
            argv[argc++] = (char *)ca_bundle_path;
        }

        if (useHappHeaders) {
            argv[argc++] = (char *)url_c;
        }
        argv[argc] = NULL;

        execv(curl_path, argv);
        _exit(127);
    }

    close(out_fd);
    close(err_fd);
    if (curl_config_fd >= 0) close(curl_config_fd);

    int status = 0;
    if (!VCWaitSubscriptionProcess(pid,&status,out_tmpl,kVCMaximumSubscriptionBytes,30,task,errOut)) {
        CleanupSubscriptionFetchTempFiles(out_tmpl,err_tmpl,hdr_tmpl);
        return nil;
    }

    NSString *out_path = [NSString stringWithUTF8String:out_tmpl];
    NSString *err_path = [NSString stringWithUTF8String:err_tmpl];
    NSString *hdr_path = [NSString stringWithUTF8String:hdr_tmpl];
    NSString *curl_err = TrimSimpleString(ReadTextFileBestEffort(err_path));
    NSString *curl_hdr = ReadTextFileBestEffort(hdr_path);
    if ([curl_err length] > 220) {
        curl_err = [curl_err substringToIndex:220];
    }

    if (headersOut) {
        *headersOut = curl_hdr;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        if (exitCodeOut && WIFEXITED(status)) {
            *exitCodeOut = WEXITSTATUS(status);
        }
        if (errOut) {
            if ([curl_err length] > 0) {
                *errOut = curl_err;
            } else if (WIFEXITED(status)) {
                *errOut = [NSString stringWithFormat:@"vless-core-curl exited with code %d", WEXITSTATUS(status)];
            } else {
                *errOut = @"vless-core-curl terminated unexpectedly";
            }
        }
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        return nil;
    }

    struct stat bodyStat;
    if (lstat(out_tmpl, &bodyStat) != 0 || !S_ISREG(bodyStat.st_mode) || bodyStat.st_nlink != 1) {
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        if (errOut) *errOut = @"Invalid subscription response file";
        return nil;
    }
    if (bodyStat.st_size <= 0) {
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        if (errOut) *errOut = @"Empty subscription response";
        return nil;
    }
    if ((uint64_t)bodyStat.st_size > kVCMaximumSubscriptionBytes) {
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
        if (errOut) *errOut = @"Subscription response exceeds 32 MiB";
        return nil;
    }

    NSData *body = [NSData dataWithContentsOfFile:out_path];
    CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);

    if (!body || [body length] == 0) {
        if (errOut) *errOut = @"Empty subscription response";
        return nil;
    }

    return body;
}
