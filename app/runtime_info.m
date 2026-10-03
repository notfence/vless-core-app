#import "app_support.h"

static NSString *RunCommandFirstLine(const char *cmdLine) {
    if (!cmdLine || !*cmdLine) return nil;

    FILE *fp = popen(cmdLine, "r");
    if (!fp) return nil;

    char buf[256];
    char *got = fgets(buf, sizeof(buf), fp);
    pclose(fp);
    if (!got) return nil;

    size_t len = strlen(buf);
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r' || buf[len - 1] == ' ' || buf[len - 1] == '\t')) {
        buf[len - 1] = '\0';
        len--;
    }
    if (len == 0) return nil;

    return [NSString stringWithUTF8String:buf];
}

NSString *DetectCoreBinaryVersion(void) {
    NSString *v = RunCommandFirstLine(VC_CORE_EXECUTABLE_PATH " -v 2>/dev/null");
    if (!v || [v length] == 0) {
        v = RunCommandFirstLine(VC_CORE_EXECUTABLE_NAME " -v 2>/dev/null");
    }
    if (!v || [v length] == 0) {
        v = @"unknown";
    }
    return v;
}

static NSString *VersionTokenAfterPrefix(NSString *line, NSString *prefix) {
    if (!line || !prefix) return @"unknown";

    NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSUInteger i = 0; i < [parts count]; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part hasPrefix:prefix] && [part length] > [prefix length]) {
            return [part substringFromIndex:[prefix length]];
        }
    }
    return @"unknown";
}

static NSString *CurlVersionFromVersionLine(NSString *line) {
    if (!line) return @"unknown";

    NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSUInteger i = 0; i < [parts count]; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part length] > 0) {
            [tokens addObject:part];
        }
    }

    if ([tokens count] >= 2 && [[tokens objectAtIndex:0] isEqualToString:@"curl"]) {
        return [tokens objectAtIndex:1];
    }
    return VersionTokenAfterPrefix(line, @"libcurl/");
}

NSDictionary *DetectCurlDependencyVersions(void) {
    NSString *line = RunCommandFirstLine("/usr/bin/vless-core-curl --version 2>/dev/null");
    if (!line || [line length] == 0) {
        line = RunCommandFirstLine("vless-core-curl --version 2>/dev/null");
    }

    NSString *curlVersion = CurlVersionFromVersionLine(line);
    NSString *opensslVersion = VersionTokenAfterPrefix(line, @"OpenSSL/");
    NSString *zlibVersion = VersionTokenAfterPrefix(line, @"zlib/");

    return [NSDictionary dictionaryWithObjectsAndKeys:
            curlVersion, @"curl",
            opensslVersion, @"openssl",
            zlibVersion, @"zlib",
            nil];
}

NSString *ReadTextFileBestEffort(NSString *path) {
    if (!path || [path length] == 0) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || [data length] == 0) return nil;

    NSString *txt = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!txt) txt = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    return txt;
}

static NSString *NormalizeOpenSSLPatchStatus(NSString *status) {
    NSString *trimmed = TrimSimpleString(status);
    if ([trimmed isEqualToString:@"patched"]) return @"patched";
    if ([trimmed isEqualToString:@"unpatched"]) return @"unpatched";
    return @"unpatched";
}

NSString *DetectOpenSSLPatchStatus(void) {
    NSString *status = ReadTextFileBestEffort(@"/usr/share/vless-core/openssl-patch-status");
    if (!status || [status length] == 0) {
        status = RunCommandFirstLine(VC_CORE_EXECUTABLE_PATH " --openssl-patch-status 2>/dev/null");
    }
    return NormalizeOpenSSLPatchStatus(status);
}

NSString *DetectRedsocksVersion(void) {
    NSString *v = RunCommandFirstLine("/usr/bin/redsocks-vless-core -v 2>/dev/null");
    if (!v || [v length] == 0) {
        v = RunCommandFirstLine("redsocks-vless-core -v 2>/dev/null");
    }
    if (!v || [v length] == 0) {
        v = @"bundled helper";
    }
    return v;
}

NSString *AppDisplayName(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *name = [info objectForKey:@"CFBundleDisplayName"];
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        name = [info objectForKey:@"CFBundleName"];
    }
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        name = @"vless-core";
    }
    return name;
}

NSString *AppShortVersion(void) {
    NSString *ver = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (![ver isKindOfClass:[NSString class]] || [ver length] == 0) {
        ver = @"0.0.0";
    }
    return ver;
}

NSString *AppUserAgent(void) {
    return [NSString stringWithFormat:@"vless-core-app/%@/iOS", AppShortVersion()];
}

typedef struct {
    const char *identifier;
    const char *name;
} VCDeviceModelEntry;

NSString *DeviceModelName(void) {
    struct utsname info;
    if (uname(&info) != 0 || info.machine[0] == '\0') {
        return TrimSimpleString([[UIDevice currentDevice] model]);
    }

    static const VCDeviceModelEntry models[] = {
        { "iPhone1,1", "iPhone" },
        { "iPhone1,2", "iPhone 3G" },
        { "iPhone2,1", "iPhone 3GS" },
        { "iPhone3,1", "iPhone 4" },
        { "iPhone3,2", "iPhone 4" },
        { "iPhone3,3", "iPhone 4" },
        { "iPhone4,1", "iPhone 4s" },
        { "iPhone5,1", "iPhone 5" },
        { "iPhone5,2", "iPhone 5" },
        { "iPhone5,3", "iPhone 5c" },
        { "iPhone5,4", "iPhone 5c" },
        { "iPhone6,1", "iPhone 5s" },
        { "iPhone6,2", "iPhone 5s" },
        { "iPhone7,1", "iPhone 6 Plus" },
        { "iPhone7,2", "iPhone 6" },
        { "iPhone8,1", "iPhone 6s" },
        { "iPhone8,2", "iPhone 6s Plus" },
        { "iPhone8,4", "iPhone SE" },
        { "iPhone9,1", "iPhone 7" },
        { "iPhone9,2", "iPhone 7 Plus" },
        { "iPhone9,3", "iPhone 7" },
        { "iPhone9,4", "iPhone 7 Plus" },
        { "iPhone10,1", "iPhone 8" },
        { "iPhone10,2", "iPhone 8 Plus" },
        { "iPhone10,3", "iPhone X" },
        { "iPhone10,4", "iPhone 8" },
        { "iPhone10,5", "iPhone 8 Plus" },
        { "iPhone10,6", "iPhone X" },
        { "iPhone11,2", "iPhone XS" },
        { "iPhone11,4", "iPhone XS Max" },
        { "iPhone11,6", "iPhone XS Max" },
        { "iPhone11,8", "iPhone XR" },
        { "iPhone12,1", "iPhone 11" },
        { "iPhone12,3", "iPhone 11 Pro" },
        { "iPhone12,5", "iPhone 11 Pro Max" },
        { "iPhone12,8", "iPhone SE (2nd generation)" },
        { "iPhone13,1", "iPhone 12 mini" },
        { "iPhone13,2", "iPhone 12" },
        { "iPhone13,3", "iPhone 12 Pro" },
        { "iPhone13,4", "iPhone 12 Pro Max" },
        { "iPad1,1", "iPad" },
        { "iPad2,1", "iPad 2" },
        { "iPad2,2", "iPad 2" },
        { "iPad2,3", "iPad 2" },
        { "iPad2,4", "iPad 2" },
        { "iPad2,5", "iPad mini" },
        { "iPad2,6", "iPad mini" },
        { "iPad2,7", "iPad mini" },
        { "iPad3,1", "iPad 3" },
        { "iPad3,2", "iPad 3" },
        { "iPad3,3", "iPad 3" },
        { "iPad3,4", "iPad 4" },
        { "iPad3,5", "iPad 4" },
        { "iPad3,6", "iPad 4" },
        { "iPad4,1", "iPad Air" },
        { "iPad4,2", "iPad Air" },
        { "iPad4,3", "iPad Air" },
        { "iPad4,4", "iPad mini 2" },
        { "iPad4,5", "iPad mini 2" },
        { "iPad4,6", "iPad mini 2" },
        { "iPad4,7", "iPad mini 3" },
        { "iPad4,8", "iPad mini 3" },
        { "iPad4,9", "iPad mini 3" },
        { "iPad5,1", "iPad mini 4" },
        { "iPad5,2", "iPad mini 4" },
        { "iPad5,3", "iPad Air 2" },
        { "iPad5,4", "iPad Air 2" },
        { "iPad6,3", "iPad Pro (9.7-inch)" },
        { "iPad6,4", "iPad Pro (9.7-inch)" },
        { "iPad6,7", "iPad Pro (12.9-inch)" },
        { "iPad6,8", "iPad Pro (12.9-inch)" },
        { "iPad6,11", "iPad (5th generation)" },
        { "iPad6,12", "iPad (5th generation)" },
        { "iPad7,1", "iPad Pro (12.9-inch) (2nd generation)" },
        { "iPad7,2", "iPad Pro (12.9-inch) (2nd generation)" },
        { "iPad7,3", "iPad Pro (10.5-inch)" },
        { "iPad7,4", "iPad Pro (10.5-inch)" },
        { "iPad7,5", "iPad (6th generation)" },
        { "iPad7,6", "iPad (6th generation)" },
        { "iPad7,11", "iPad (7th generation)" },
        { "iPad7,12", "iPad (7th generation)" },
        { "iPad8,1", "iPad Pro (11-inch)" },
        { "iPad8,2", "iPad Pro (11-inch)" },
        { "iPad8,3", "iPad Pro (11-inch)" },
        { "iPad8,4", "iPad Pro (11-inch)" },
        { "iPad8,5", "iPad Pro (12.9-inch) (3rd generation)" },
        { "iPad8,6", "iPad Pro (12.9-inch) (3rd generation)" },
        { "iPad8,7", "iPad Pro (12.9-inch) (3rd generation)" },
        { "iPad8,8", "iPad Pro (12.9-inch) (3rd generation)" },
        { "iPad8,9", "iPad Pro (11-inch) (2nd generation)" },
        { "iPad8,10", "iPad Pro (11-inch) (2nd generation)" },
        { "iPad8,11", "iPad Pro (12.9-inch) (4th generation)" },
        { "iPad8,12", "iPad Pro (12.9-inch) (4th generation)" },
        { "iPad11,1", "iPad mini (5th generation)" },
        { "iPad11,2", "iPad mini (5th generation)" },
        { "iPad11,3", "iPad Air (3rd generation)" },
        { "iPad11,4", "iPad Air (3rd generation)" },
        { "iPad11,6", "iPad (8th generation)" },
        { "iPad11,7", "iPad (8th generation)" },
        { "iPad13,1", "iPad Air (4th generation)" },
        { "iPad13,2", "iPad Air (4th generation)" },
        { "iPad13,4", "iPad Pro (11-inch) (3rd generation)" },
        { "iPad13,5", "iPad Pro (11-inch) (3rd generation)" },
        { "iPad13,6", "iPad Pro (11-inch) (3rd generation)" },
        { "iPad13,7", "iPad Pro (11-inch) (3rd generation)" },
        { "iPad13,8", "iPad Pro (12.9-inch) (5th generation)" },
        { "iPad13,9", "iPad Pro (12.9-inch) (5th generation)" },
        { "iPad13,10", "iPad Pro (12.9-inch) (5th generation)" },
        { "iPad13,11", "iPad Pro (12.9-inch) (5th generation)" },
        { "iPod1,1", "iPod touch" },
        { "iPod2,1", "iPod touch (2nd generation)" },
        { "iPod3,1", "iPod touch (3rd generation)" },
        { "iPod4,1", "iPod touch (4th generation)" },
        { "iPod5,1", "iPod touch (5th generation)" },
        { "iPod7,1", "iPod touch (6th generation)" },
        { "iPod9,1", "iPod touch (7th generation)" }
    };

    for (size_t i = 0; i < sizeof(models) / sizeof(models[0]); i++) {
        if (strcmp(info.machine, models[i].identifier) == 0) {
            return [NSString stringWithUTF8String:models[i].name];
        }
    }
    return [NSString stringWithUTF8String:info.machine];
}

NSString *AppBuildVersion(void) {
    NSString *build = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    if (![build isKindOfClass:[NSString class]] || [build length] == 0) {
        build = @"0";
    }
    return build;
}

NSString *AppVersionSummary(void) {
    return [NSString stringWithFormat:@"Version %@ (%@)", AppShortVersion(), AppBuildVersion()];
}

static NSString *AppInfoString(NSString *key, NSString *fallback) {
    NSString *value = [[[NSBundle mainBundle] infoDictionary] objectForKey:key];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
        return fallback;
    }
    return value;
}

static NSString *AppDebBuildDate(void) {
    return AppInfoString(@"VCBuildDate", @"unknown");
}

static NSString *AppGitShortCommit(void) {
    return AppInfoString(@"VCGitCommit", @"unknown");
}

NSString *AppBuildMetadataSummary(void) {
    return [NSString stringWithFormat:@"Built at: %@\nGitSHA: %@", AppDebBuildDate(), AppGitShortCommit()];
}

NSString *SubscriptionHWID(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *hwid = [ud objectForKey:kDefaultsSubHWIDKey];
    if ([hwid isKindOfClass:[NSString class]] && [hwid length] > 0) {
        return hwid;
    }

    NSString *generated = nil;
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    if (uuid) {
        CFStringRef cf = CFUUIDCreateString(kCFAllocatorDefault, uuid);
        if (cf) {
            generated = [NSString stringWithString:(NSString *)cf];
            CFRelease(cf);
        }
        CFRelease(uuid);
    }

    if (![generated isKindOfClass:[NSString class]] || [generated length] == 0) {
        generated = [NSString stringWithFormat:@"%u-%u-%u",
                     (unsigned)arc4random(),
                     (unsigned)arc4random(),
                     (unsigned)getpid()];
    }

    [ud setObject:generated forKey:kDefaultsSubHWIDKey];
    [ud synchronize];
    return generated;
}
